
Velero (velero)

# Create the isolated namespace first
kubectl create namespace velero

# Install Velero via Helm
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo update



Push the policy to AWS
Run this in your terminal to create the policy:

policyArn=$(aws iam create-policy --policy-name VeleroPracticePolicy --policy-document file://velero-policy.json --query 'Policy.Arn' --output text --profile eml-eks)

Use this format to create your IAM service account:

eksctl create iamserviceaccount \
  --cluster=YOUR_PRACTICE_CLUSTER_NAME \
  --region=eu-west-3 \
  --namespace=velero \
  --name=velero-server \
  --attach-policy-arn=$policyArn \
  --approve \
  --override-existing-serviceaccounts


# 1. Create the IAM Service Account using your profile
eksctl create iamserviceaccount \
  --cluster=YOUR_PRACTICE_CLUSTER_NAME \
  --region=eu-west-3 \
  --namespace=velero \
  --name=velero-server \
  --attach-policy-arn=$policyArn \
  --approve \
  --override-existing-serviceaccounts \
  --profile eml-eks

# Delete the failing deployment cleanly
kubectl delete deployment velero -n velero --force --grace-period=0

# Ensure you have the latest repo charts
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo update

# Reinstall with the latest recommended chart and versions
helm upgrade --install velero vmware-tanzu/velero \
  --namespace velero \
  --create-namespace \
  --set configuration.backupStorageLocation[0].name=aws \
  --set configuration.backupStorageLocation[0].provider=aws \
  --set configuration.backupStorageLocation[0].bucket=eml-eks-demo \
  --set configuration.backupStorageLocation[0].config.region=eu-west-3 \
  --set configuration.volumeSnapshotLocation[0].name=aws \
  --set configuration.volumeSnapshotLocation[0].provider=aws \
  --set configuration.volumeSnapshotLocation[0].config.region=eu-west-3 \
  --set initContainers[0].name=velero-plugin-for-aws \
  --set initContainers[0].image=velero/velero-plugin-for-aws:v1.14.0 \
  --set initContainers[0].volumeMounts[0].mountPath=/plugins \
  --set initContainers[0].volumeMounts[0].name=plugins \
  --set credentials.useSecret=false \
  --set serviceAccount.server.create=true \
  --set serviceAccount.server.name=velero-server \
  --set serviceAccount.server.annotations."eks\.amazonaws\.com/role-arn"="arn:aws:iam::204687258296:role/VeleroPracticeRole"

wget https://github.com/vmware-tanzu/velero/releases/download/v1.18.1/velero-v1.18.1-linux-amd64.tar.gz
tar -xvf velero-v1.18.1-linux-amd64.tar.gz
sudo mv velero-v1.18.1-linux-amd64/velero /usr/local/bin/velero



velero install --help  # or use kubectl to check
kubectl get backupstoragelocations -n velero


