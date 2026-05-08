# terraform/environments/staging/main.tf

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# No bug here — data source is valid; account_id used in the eks module for IRSA.
data "aws_caller_identity" "this" {}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  cluster_name = "${var.project}-${var.environment}-eks"
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.2"

  name = "${local.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  # FIX (Bug 1): ELB subnet discovery tags must use the string "1", not the integer 0.
  # AWS requires exactly the string "1" for these tags; any other value causes EKS to
  # skip the subnet when provisioning load balancers.
  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "owned"
    "kubernetes.io/role/elb"                      = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "owned"
    "kubernetes.io/role/internal-elb"             = "1"
  }

  tags = local.common_tags
}

module "eks" {
  source = "../../modules/eks-cluster"

  cluster_name    = local.cluster_name
  cluster_version = var.cluster_version
  environment     = var.environment
  vpc_id          = module.vpc.vpc_id

  # FIX (Bug 2): Control-plane ENIs must live in private subnets.
  # Using public_subnets exposes the Kubernetes API endpoint to the public internet
  # and breaks private-endpoint-only configurations.
  subnet_ids = module.vpc.private_subnets

  node_group_subnet_ids = module.vpc.private_subnets

  # Required for the IRSA S3 policy (Task 1b)
  app_bucket_name = var.app_bucket_name

  tags = local.common_tags
}
