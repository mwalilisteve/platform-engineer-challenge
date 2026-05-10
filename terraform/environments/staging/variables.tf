variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "af-south-1"
}

variable "project" {
  description = "Project name — used in resource naming and tags"
  type        = string
  default     = "acme"
}

variable "environment" {
  description = "Deployment environment (staging, production)"
  type        = string
  default     = "staging"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.10.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "List of CIDRs for private subnets (one per AZ)"
  type        = list(string)
  default     = ["10.10.0.0/19", "10.10.32.0/19", "10.10.64.0/19"]
}

variable "public_subnet_cidrs" {
  description = "List of CIDRs for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.10.96.0/19", "10.10.128.0/19", "10.10.160.0/19"]
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.30"
}

variable "node_instance_type" {
  description = "EC2 instance type for the managed node group"
  type        = string
  default     = "t3.medium"
}

variable "node_desired_size" {
  description = "Desired number of nodes in the managed node group"
  type        = number
  default     = 1
}

variable "node_min_size" {
  description = "Minimum number of nodes in the managed node group"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of nodes in the managed node group"
  type        = number
  default     = 3
}

variable "app_sa_namespace" {
  description = "Kubernetes namespace the app service account lives in"
  type        = string
  default     = "default"
}

variable "app_sa_name" {
  description = "Kubernetes service account name that will assume the IRSA role"
  type        = string
  default     = "app-sa"
}

variable "app_bucket_name" {
  description = "Name of the S3 bucket the application service account needs access to"
  type        = string
}

variable "state_bucket" {
  description = "S3 bucket name used for Terraform remote state"
  type        = string
  default     = "acme-terraform-state"
}

variable "state_lock_table" {
  description = "DynamoDB table name used for Terraform state locking"
  type        = string
  default     = "acme-terraform-locks"
}