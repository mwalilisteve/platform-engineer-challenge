# modules/eks-cluster/variables.tf

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID to deploy the cluster into"
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for the EKS control plane"
  type        = list(string)
}

variable "node_group_subnet_ids" {
  description = "Subnet IDs for the managed node group"
  type        = list(string)
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
variable "app_bucket_name" {
  description = "Name of the S3 bucket the app-sa service account needs access to (used for IRSA policy)"
  type        = string
}
