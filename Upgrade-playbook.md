
Part 2: The EKS Upgrade Execution Playbook
EKS upgrades follow a strict architectural dependency chain. You must work from the top down. If you reverse or skip any of these steps, you risk breaking network paths or preventing pods from scheduling.

Step 1: Preflight API Sanity Check
Before executing the upgrade via AWS, check your practice apps for any deprecated Kubernetes objects. Run kubent to automatically verify your cluster state:

sh -c "$(curl -sSL https://git.io/install-kubent)" | kubent

Step 2: Upgrade the EKS Control Plane (The Brain)
Change the Kubernetes target version parameter to match exactly one minor version higher than what your practice cluster is running right now. Do not skip versions (e.g., if you are currently running 1.33, target 1.34).

Run the update via the AWS CLI:

aws eks update-cluster-version \
  --region eu-west-3 \
  --name YOUR_PRACTICE_CLUSTER_NAME \
  --kubernetes-version 1.34


What happens now: AWS will provision a new, parallel control plane and cleanly migrate your cluster configuration behind the scenes. Your worker nodes and your applications will stay up and keep running. You can track its progress with this loop:


while true; do
  STATUS=$(aws eks describe-cluster --name YOUR_PRACTICE_CLUSTER_NAME --query "cluster.status" --output text)
  echo "$(date): Cluster is $STATUS"
  [ "$STATUS" = "ACTIVE" ] && break
  sleep 30
done


Step 3: Upgrade Core Networking Add-ons
Once the control plane reads ACTIVE, you must manually upgrade your managed EKS add-ons to line up with your new minor version. Update them in this exact order:

kube-proxy

Amazon VPC CNI

CoreDNS (Always update CoreDNS last to keep cluster internal resolution stable)

Find the target versions recommended for your new cluster version:

aws eks describe-addon-versions --kubernetes-version 1.34


Then execute the update for each add-on:

aws eks update-addon --cluster-name YOUR_PRACTICE_CLUSTER_NAME --addon-name vpc-cni --addon-version <RECOMMENDED_VERSION>
aws eks update-addon --cluster-name YOUR_PRACTICE_CLUSTER_NAME --addon-name kube-proxy --addon-version <RECOMMENDED_VERSION>
aws eks update-addon --cluster-name YOUR_PRACTICE_CLUSTER_NAME --addon-name coredns --addon-version <RECOMMENDED_VERSION>

Step 4: Upgrade the Managed Node Groups (The Data Plane)
This is where your practice applications (the Online Boutique and mock statefulsets) face their true test. Upgrading the Node Group tells AWS to spin up new EC2 instances running the updated AMI, then safely cordon and drain the old ones.

aws eks update-nodegroup-version \
  --cluster-name YOUR_PRACTICE_CLUSTER_NAME \
  --nodegroup-name YOUR_NODE_GROUP_NAME \
  --kubernetes-version 1.34

What to watch closely during the node migration:
Open a separate terminal window and keep a close eye on the pod transitions while the data plane upgrades:

kubectl get pods -A -w

