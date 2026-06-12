# Quick Velero Setup on EKS (Recommended with EKS Pod Identity + CSI Snapshots)

helm search repo velero

## Create an S3 bucket for backups.
## Install the snapshot-controller EKS add-on (required for volume snapshots):Bash

aws eks create-addon --cluster-name <cluster> --addon-name snapshot-controller

## Install Velero via Helm (example with least-privilege setup):

helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts

create a values.yaml  # configuring S3, region, and Pod Identity (no static credentials).

## policy creation part

# install velero
helm install velero vmware-tanzu/velero --namespace velero --create-namespace --values velero-values.yaml
# update instead of recreate
helm upgrade velero vmware-tanzu/velero --namespace velero --create-namespace --values velero-values.yaml

# then create pod identity permision -- visit policy-readme.md and role-attach-policy.sh files

aws eks create-pod-identity-association \
  --cluster-name eml-eks \
  --namespace velero \
  --service-account velero-server \
  --role-arn arn:aws:iam::858112817679:role/VeleroRole-eks-dev \
  --profile eml-eks

## VolumeSnapshotClass
This is separate from the Helm values.yaml. 
## You must create it after installing Velero and the snapshot-controller add-on.
It tells Velero (and the CSI driver) how to create EBS snapshots.
Create this YAML and apply it:

# YAML
# Save as snapshotclass.yaml

apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: velero-ebs-snapshotclass
  labels:
    velero.io/csi-volumesnapshot-class: "true"
  annotations:
    snapshot.storage.kubernetes.io/is-default-class: "true"
driver: ebs.csi.eks.amazonaws.com
deletionPolicy: Delete


kubectl apply -f snapshot-class.yaml

## Create a default VolumeSnapshotClass for EBS CSI.

# more comprehensive
velero backup create pre-upgrade-backup-test \
  --include-cluster-resources=true \
  --snapshot-volumes \
  --wait

# just the namespaces
velero backup create full-backup --include-namespaces '*' --wait

velero backup describe full-backup

# example
velero backup create pre-upgrade-1-34 --include-namespaces '*' --wait


# Verify with : 

velero backup get

# Upgrade Process (One Minor Version at a Time)

## For each step (e.g., 1.33 → 1.34, then repeat for next):

Upgrade Control Plane:
AWS Console: EKS → Cluster → Upgrade now → Select next version.
# Or CLI:Bash

aws eks update-cluster-version --name <cluster-name> --kubernetes-version 1.34

## Monitor with
aws eks describe-cluster --name <cluster-name> --query "cluster.status"

aws eks describe-cluster   --name eml-eks   --query "cluster.status" --profile eml-eks


## Upgrade Add-ons:
Update EKS-managed add-ons via Console/CLI to compatible versions.
Update self-managed ones (e.g., via Helm).

## Upgrade Data Plane (Nodes):

Managed Node Groups: Update via Console 

## or 

aws eks update-nodegroup-version

Karpenter: Use drift/upgrade features or replace nodes.
Self-managed: Roll out new launch templates with newer EKS-optimized AMIs and drain old nodes.
Fargate: Redeploy pods after control plane upgrade.

## Validate: 
kubectl get nodes, pods, services, ingress, etc.
Monitor applications and logs.
Run test workloads.

# Additional Tips & Best Practices

Velero Ongoing Use:
Set up schedules: velero schedule create daily --schedule "0 2 * * *" --include-namespaces '*'
Use for DR, namespace migrations, or cluster cloning.
Store backups with encryption and lifecycle policies in S3.


Layer 1 — Scheduled backups (automatic)

Example:

daily backup
retention 7–30 days

velero schedule create daily-backup \
  --schedule="0 2 * * *" \
  --include-namespaces '*'
