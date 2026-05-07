# terraform/environments/staging/main.tf
# This file has intentional bugs. Find and fix them.
# Document each fix with a comment explaining what was wrong.

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

# BUG: Data source is referencing a non-existent attribute
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

  # BUG: These tags are required for EKS to discover subnets, but the values are wrong
  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "owned"
    "kubernetes.io/role/elb"                      = 0
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "owned"
    "kubernetes.io/role/internal-elb"             = 0
  }

  tags = local.common_tags
}

module "eks" {
  source = "../../modules/eks-cluster"

  cluster_name    = local.cluster_name
  cluster_version = var.cluster_version
  environment     = var.environment
  vpc_id          = module.vpc.vpc_id

  # BUG: This is passing public subnets for the control plane — should be private
  subnet_ids = module.vpc.public_subnets

  node_group_subnet_ids = module.vpc.private_subnets

  tags = local.common_tags
}
