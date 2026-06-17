
# 1. Check BackupStorageLocation status
velero backup-location get
velero backup-location get default

velero backup describe full-backup

velero backup logs full-backup-2

# 2. Check Velero pod logs for detailed error
kubectl -n velero logs deployment/velero --tail=100

kubectl -n velero rollout restart deployment/velero
kubectl -n velero rollout status deployment/velero


velero backup create full-backup2 --include-namespaces '*' --wait


kubectl -n velero run -it --rm aws-cli --image=amazon/aws-cli --command -- /bin/sh
# Inside the pod run:
aws sts get-caller-identity
aws s3 ls s3://eml-eks-demo --region eu-west-3
exit

# test cli sa
apiVersion: v1
kind: Pod
metadata:
  name: aws-cli
  namespace: velero
spec:
  serviceAccountName: velero-server
  containers:
  - name: aws-cli
    image: amazon/aws-cli
    command: ["sleep","3600"]


velero backup logs full-backup-2

velero backup describe full-backup-2

velero backup get

# test restore

velero restore create --from-backup full-backup

error addons 

Metric server (ConfigurationConflict)

aws eks update-addon \
  --cluster-name <cluster> \
  --addon-name metrics-server \
  --addon-version v0.8.0-eksbuild.1 \
  --resolve-conflicts OVERWRITE