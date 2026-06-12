
S3 part: Full access to your backup bucket.
EC2 part: Needed for EBS volume snapshots.


Before installing:

Create S3 bucket.
Create IAM Role with policies: AmazonS3FullAccess (or least-privilege), AmazonEC2FullAccess (for snapshots), and trust relationship for EKS Pod Identity.
Attach the role to Velero's ServiceAccount via Pod Identity Association.

Create a least-privilege IAM policy and attach it to the IAM role. Here is a standard, recommended policy for Velero on EKS with CSI snapshots: