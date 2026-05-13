terraform {
  backend "s3" {
    bucket         = "acme-terraform-state"
    key            = "staging/eks-cluster/terraform.tfstate"
    region         = "af-south-1"
    dynamodb_table = "acme-terraform-locks"
    encrypt        = true
  }
}