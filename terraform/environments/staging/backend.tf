# terraform/environments/staging/backend.tf
# Remote state using S3 + DynamoDB locking.
# The bucket and DynamoDB table must be pre-created (bootstrapped) before running
# terraform init here — they are not managed by this workspace to avoid a
# chicken-and-egg dependency.

terraform {
  backend "s3" {
    # Replace with your actual state bucket name.
    # Recommended naming: <org>-terraform-state-<account-id>
    bucket = "acme-terraform-state"

    # Key is scoped per environment so staging and production share the
    # same bucket without risk of overwriting each other's state.
    key = "staging/eks-cluster/terraform.tfstate"

    region = "af-south-1"

    # DynamoDB table used for state locking and consistency checks.
    # Partition key must be "LockID" (string) — this is an AWS requirement.
    dynamodb_table = "acme-terraform-locks"

    # Always encrypt state at rest. If your bucket has default SSE-S3,
    # this is a no-op; for SSE-KMS set kms_key_id instead.
    encrypt = true
  }
}
