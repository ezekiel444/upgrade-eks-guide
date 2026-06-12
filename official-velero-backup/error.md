
 aws eks create-pod-identity-association   --cluster-name eml-eks   --namespace velero   --service-account velero   --role-arn arn:aws:iam::204687258296:role/VeleroRole --profile eml-eks

aws: [ERROR]: An error occurred (AccessDeniedException) when calling the CreatePodIdentityAssociation operation: User: arn:aws:iam::204687258296:user/eml-eks is not authorized to perform: iam:PassRole on resource: arn:aws:iam::204687258296:role/VeleroRole because no identity-based policy allows the iam:PassRole action

# Solution

Fix: Add iam:PassRole Permission
Option 1: Quick Fix (Recommended for now)
Create a new inline policy or attach this to your eml-eks user/role:
# to this
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "iam:PassRole",
        "iam:GetRole"
      ],
      "Resource": "arn:aws:iam::204687258296:role/VeleroRole"
    }
  ]
}
