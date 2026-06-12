Step-by-Step in AWS Console

Go to IAM → Roles → Create role
Trusted entity type:
Select Custom trust policy (this is the correct one)

Trust policy (paste this JSON in the editor):

## json

{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "pods.eks.amazonaws.com"
      },
      "Action": [
        "sts:AssumeRole",
        "sts:TagSession"
      ]
    }
  ]
}


Permissions:
Attach the policy you already created (the one with S3 + EC2 permissions for Velero)

name : VeleroRole

# alternatively, you can create the role using AWS CLI with the following command:

aws iam create-role \
  --role-name VeleroRole \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Service": "pods.eks.amazonaws.com"
        },
        "Action": [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  }'