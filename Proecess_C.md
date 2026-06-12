# EKS Upgrade Guide: 1.33 → 1.34 → 1.35

> **Manual deployment on AWS (no IaC)**  
> Backup strategy: Velero + S3  
> Last updated: June 2026

---

## Context & Version Timeline

| EKS Version | Standard Support End | Extended Support End | Status |
|---|---|---|---|
| 1.33 | **July 29, 2026** | ~July 2027 | ⚠️ Upgrade soon |
| 1.34 | December 02, 2026 | ~December 2027 | ✅ Active |
| 1.35 | March 27, 2027 | ~March 2028 | ✅ Active (recommended target) |

> EKS does not have an official "LTS" label. **1.35** is the recommended target — it gives the longest support runway as of today.

**Upgrade path (mandatory, one minor version at a time):**
```
1.33 → 1.34 → 1.35
```

> ⚠️ **AL2 → AL2023 note:** From EKS 1.33 onwards, Amazon Linux 2 AMIs are no longer released. If your nodes run AL2, you must migrate to AL2023 during the 1.33 → 1.34 step. A new node group is the recommended approach for this migration.

---

## Prerequisites

Before starting any upgrade:

- [ ] AWS CLI configured with sufficient IAM permissions (`eks:UpdateClusterVersion`, `eks:UpdateNodegroupVersion`, `ec2:*` for snapshots, `s3:*` for Velero bucket)
- [ ] `kubectl` configured and pointing to the correct cluster
- [ ] `velero` CLI installed locally
- [ ] `kubent` (kube-no-trouble) installed for API deprecation scanning
- [ ] A dedicated S3 bucket for Velero backups created in your region
- [ ] Maintenance window scheduled (control plane upgrade: ~15 min, node rolling update: varies)

---

## Phase 0 — Pre-flight Checks

> Run these checks **before every upgrade cycle**, not just the first one.

### 0.1 — Check current cluster version

```bash
aws eks describe-cluster \
  --name <cluster-name> \
  --region <region> \
  --query "cluster.version"
```

### 0.2 — Run EKS Upgrade Insights (AWS Console)

1. Go to **EKS → Your Cluster → Upgrade Insights tab**
2. Review any flagged issues (deprecated APIs, incompatible add-ons)
3. Resolve all blockers before proceeding

### 0.3 — Scan for deprecated APIs with kubent

```bash
# Install kubent if not already installed
brew install kubent   # macOS
# or: https://github.com/doitintl/kube-no-trouble/releases

# Run against your cluster
kubent
```

Fix any deprecated API usage in your manifests before upgrading.

### 0.4 — List current add-on versions

```bash
aws eks list-addons \
  --cluster-name <cluster-name> \
  --region <region>

# Get version details for each add-on
aws eks describe-addon \
  --cluster-name <cluster-name> \
  --addon-name vpc-cni \
  --region <region> \
  --query "addon.addonVersion"
```

Repeat for: `coredns`, `kube-proxy`, `aws-ebs-csi-driver`.

### 0.5 — Check node AMI type

```bash
aws eks describe-nodegroup \
  --cluster-name <cluster-name> \
  --nodegroup-name <nodegroup-name> \
  --region <region> \
  --query "nodegroup.amiType"
```

If the result is `AL2_x86_64` or `AL2_ARM_64`, you are on Amazon Linux 2 and **must migrate to AL2023** during the 1.33 → 1.34 step (see Phase 2B).

---

## Phase 1 — Velero Setup & Pre-Upgrade Backup

> Take a full backup before **each** minor version upgrade.

### 1.1 — Create S3 bucket for backups (one-time)

```bash
BUCKET_NAME="eks-velero-backup-$(date +%Y%m%d)"
REGION="<your-region>"

aws s3 mb s3://$BUCKET_NAME --region $REGION

# Enable versioning (recommended)
aws s3api put-bucket-versioning \
  --bucket $BUCKET_NAME \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket $BUCKET_NAME \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
```

### 1.2 — Create IAM policy for Velero (one-time)

Create a file `velero-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeVolumes",
        "ec2:DescribeSnapshots",
        "ec2:CreateSnapshot",
        "ec2:DeleteSnapshot",
        "ec2:DescribeTags",
        "ec2:CreateTags"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:PutObject",
        "s3:AbortMultipartUpload",
        "s3:ListMultipartUploadParts"
      ],
      "Resource": "arn:aws:s3:::YOUR_BUCKET_NAME/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket"
      ],
      "Resource": "arn:aws:s3:::YOUR_BUCKET_NAME"
    }
  ]
}
```

```bash
# Create IAM policy
aws iam create-policy \
  --policy-name VeleroEKSPolicy \
  --policy-document file://velero-policy.json

# Create IAM user for Velero
aws iam create-user --user-name velero

# Attach policy
aws iam attach-user-policy \
  --user-name velero \
  --policy-arn arn:aws:iam::<account-id>:policy/VeleroEKSPolicy

# Generate credentials
aws iam create-access-key --user-name velero
# Save the AccessKeyId and SecretAccessKey
```

### 1.3 — Install Velero in the cluster (one-time)

```bash
# Create credentials file
cat > /tmp/velero-credentials << EOF
[default]
aws_access_key_id=<AccessKeyId>
aws_secret_access_key=<SecretAccessKey>
EOF

# Install Velero
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.10.0 \
  --bucket $BUCKET_NAME \
  --secret-file /tmp/velero-credentials \
  --backup-location-config region=$REGION \
  --snapshot-location-config region=$REGION \
  --use-node-agent

# Verify installation
kubectl get pods -n velero
velero version
```

### 1.4 — Take pre-upgrade backup

```bash
# Before upgrading 1.33 → 1.34
velero backup create pre-upgrade-133-to-134 \
  --include-namespaces "*" \
  --default-volumes-to-fs-backup \
  --wait

# Verify backup
velero backup describe pre-upgrade-133-to-134
velero backup get
```

> The backup is stored in your S3 bucket. Verify in the AWS console that the objects are present before proceeding.

---

## Phase 2 — Upgrade 1.33 → 1.34

### 2.1 — Upgrade the control plane

```bash
aws eks update-cluster-version \
  --name <cluster-name> \
  --kubernetes-version 1.34 \
  --region <region>

# Monitor — takes ~10-15 minutes
watch aws eks describe-cluster \
  --name <cluster-name> \
  --region <region> \
  --query "cluster.status"

# Wait until status is ACTIVE
aws eks wait cluster-active --name <cluster-name> --region <region>

# Confirm version
aws eks describe-cluster \
  --name <cluster-name> \
  --region <region> \
  --query "cluster.version"
```

### 2.2 — Upgrade add-ons

Always upgrade add-ons **after** the control plane, **before** nodes.

```bash
# Upgrade each add-on (repeat for all)
for ADDON in vpc-cni coredns kube-proxy aws-ebs-csi-driver; do
  echo "Upgrading $ADDON..."
  aws eks update-addon \
    --cluster-name <cluster-name> \
    --addon-name $ADDON \
    --resolve-conflicts OVERWRITE \
    --region <region>
done

# Verify add-ons are active
aws eks list-addons \
  --cluster-name <cluster-name> \
  --region <region>
```

> For each add-on, check the compatible version for 1.34 in the [EKS add-on docs](https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html) and specify `--addon-version` if needed.

### 2.3A — Upgrade node group (AL2023 nodes, no migration needed)

If your nodes are already on AL2023:

```bash
aws eks update-nodegroup-version \
  --cluster-name <cluster-name> \
  --nodegroup-name <nodegroup-name> \
  --region <region>

# Monitor
aws eks describe-nodegroup \
  --cluster-name <cluster-name> \
  --nodegroup-name <nodegroup-name> \
  --region <region> \
  --query "nodegroup.status"
```

AWS performs a rolling update: cordon → drain → terminate → launch new node, one at a time.

### 2.3B — Migrate node group from AL2 → AL2023 (if applicable)

> Required if your nodes are on Amazon Linux 2. A new node group is the cleanest approach.

```bash
# Step 1: Create new node group with AL2023
aws eks create-nodegroup \
  --cluster-name <cluster-name> \
  --nodegroup-name <nodegroup-name>-al2023 \
  --node-role <node-role-arn> \
  --subnets <subnet-ids> \
  --ami-type AL2023_x86_64_STANDARD \
  --instance-types <instance-type> \
  --scaling-config minSize=<min>,maxSize=<max>,desiredSize=<desired> \
  --kubernetes-version 1.34 \
  --region <region>

# Step 2: Wait for new node group to be Active
aws eks wait nodegroup-active \
  --cluster-name <cluster-name> \
  --nodegroup-name <nodegroup-name>-al2023 \
  --region <region>

# Step 3: Cordon all old (AL2) nodes
kubectl get nodes -l eks.amazonaws.com/nodegroup=<old-nodegroup-name> \
  -o name | xargs kubectl cordon

# Step 4: Drain old nodes (one at a time or all)
kubectl get nodes -l eks.amazonaws.com/nodegroup=<old-nodegroup-name> \
  -o name | xargs -I {} kubectl drain {} \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --force

# Step 5: Verify all pods are running on new nodes
kubectl get pods -A -o wide

# Step 6: Delete old node group
aws eks delete-nodegroup \
  --cluster-name <cluster-name> \
  --nodegroup-name <old-nodegroup-name> \
  --region <region>
```

### 2.4 — Validate 1.34 upgrade

```bash
# Check all nodes are on 1.34 and Ready
kubectl get nodes

# Check all system pods are healthy
kubectl get pods -n kube-system

# Check application pods
kubectl get pods -A | grep -v Running | grep -v Completed
```

---

## Phase 3 — Velero Backup Before 1.34 → 1.35

```bash
velero backup create pre-upgrade-134-to-135 \
  --include-namespaces "*" \
  --default-volumes-to-fs-backup \
  --wait

velero backup describe pre-upgrade-134-to-135
```

---

## Phase 4 — Upgrade 1.34 → 1.35

### 4.1 — Pre-flight checks (repeat Phase 0)

Run kubent again to catch any new deprecations introduced between 1.34 and 1.35:

```bash
kubent
```

> ⚠️ **1.35 specific:** The `--pod-infra-container-image` kubelet flag has been removed. If you use custom AMIs or custom launch templates that set this flag, remove it before upgrading.

### 4.2 — Upgrade control plane

```bash
aws eks update-cluster-version \
  --name <cluster-name> \
  --kubernetes-version 1.35 \
  --region <region>

aws eks wait cluster-active --name <cluster-name> --region <region>

aws eks describe-cluster \
  --name <cluster-name> \
  --region <region> \
  --query "cluster.version"
```

### 4.3 — Upgrade add-ons

```bash
for ADDON in vpc-cni coredns kube-proxy aws-ebs-csi-driver; do
  echo "Upgrading $ADDON..."
  aws eks update-addon \
    --cluster-name <cluster-name> \
    --addon-name $ADDON \
    --resolve-conflicts OVERWRITE \
    --region <region>
done
```

### 4.4 — Upgrade node group

```bash
aws eks update-nodegroup-version \
  --cluster-name <cluster-name> \
  --nodegroup-name <nodegroup-name> \
  --region <region>

# Monitor until ACTIVE
aws eks describe-nodegroup \
  --cluster-name <cluster-name> \
  --nodegroup-name <nodegroup-name> \
  --region <region> \
  --query "nodegroup.status"
```

### 4.5 — Final validation

```bash
# All nodes on 1.35 and Ready
kubectl get nodes

# No unhealthy pods
kubectl get pods -A | grep -v Running | grep -v Completed

# Check cluster version
kubectl version --short
```

---

## Phase 5 — Post-Upgrade

### 5.1 — Take a final backup

```bash
velero backup create post-upgrade-135 \
  --include-namespaces "*" \
  --default-volumes-to-fs-backup \
  --wait

velero backup describe post-upgrade-135
```

### 5.2 — Set up scheduled backups

```bash
# Daily backup at 2am, keep 7 days
velero schedule create daily-backup \
  --schedule="0 2 * * *" \
  --include-namespaces "*" \
  --default-volumes-to-fs-backup \
  --ttl 168h0m0s

velero schedule get
```

### 5.3 — Set upgrade policy to avoid auto-upgrade

```bash
# Set to STANDARD to get auto-upgraded at end of standard support
# Set to EXTENDED if you want to stay on the version longer (extra cost)
aws eks update-cluster \
  --name <cluster-name> \
  --upgrade-policy supportType=STANDARD \
  --region <region>
```

### 5.4 — Clean up old Velero backups (optional)

```bash
velero backup delete pre-upgrade-133-to-134
velero backup delete pre-upgrade-134-to-135
```

> ⚠️ Deleting a Velero backup also removes it from S3. Keep at least one backup at all times.

---

## Rollback: How to Restore with Velero

> EKS does not support downgrading a control plane version. Velero restores **workloads and data**, not the control plane version. Use this if a deployment or namespace was accidentally lost.

```bash
# List available backups
velero backup get

# Restore a specific namespace
velero restore create \
  --from-backup pre-upgrade-133-to-134 \
  --include-namespaces <namespace>

# Restore everything
velero restore create \
  --from-backup pre-upgrade-133-to-134

# Check restore status
velero restore describe <restore-name>
velero restore logs <restore-name>
```

---

## Quick Reference: Upgrade Order (Always)

```
1. Control Plane upgrade
2. Add-ons upgrade (vpc-cni, coredns, kube-proxy, ebs-csi)
3. Node groups upgrade (rolling update or new NG for AL2→AL2023)
```

Never upgrade nodes before the control plane. Never skip minor versions.

---

## Useful Commands Cheatsheet

```bash
# Check cluster version
aws eks describe-cluster --name <cluster> --query "cluster.version"

# Check node versions
kubectl get nodes -o wide

# Check add-on versions
aws eks list-addons --cluster-name <cluster>

# Check pod health
kubectl get pods -A | grep -v Running | grep -v Completed

# Velero backup list
velero backup get

# Velero restore list
velero restore get

# EKS upgrade insights
aws eks list-insights --cluster-name <cluster>
```