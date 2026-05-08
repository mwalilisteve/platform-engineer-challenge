# terraform/modules/eks-cluster/main.tf
#
# FIX (Bug 3): The original file was a copy of the root variables.tf — it contained
# only variable declarations and defined no resources at all. outputs.tf referenced
# aws_eks_cluster.this, aws_iam_openid_connect_provider.this, and aws_iam_role.node_group,
# none of which existed. This file now defines all required resources.
#
# FIX (Bug 4): The original node group lacked instance_types, used hard-coded
# scaling values, and had no launch template for environment tagging. Fixed below.

data "aws_caller_identity" "this" {}
data "aws_partition" "current" {}

# ── Cluster IAM role ──────────────────────────────────────────────────────────

resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSClusterPolicy" {
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

# ── EKS Cluster ───────────────────────────────────────────────────────────────

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  depends_on = [aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy]

  tags = var.tags
}

# ── OIDC provider (required for IRSA) ────────────────────────────────────────

data "tls_certificate" "this" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "this" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.this.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer

  tags = var.tags
}

# ── IRSA — app-sa service account (Task 1b) ───────────────────────────────────
# Allows the Kubernetes service account "app-sa" in namespace "default" to assume
# this role via OIDC federation, granting least-privilege S3 access.

locals {
  oidc_provider_id = replace(aws_iam_openid_connect_provider.this.url, "https://", "")
}

resource "aws_iam_role" "app_sa" {
  name = "${var.cluster_name}-app-sa-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.this.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_provider_id}:sub" = "system:serviceaccount:default:app-sa"
          "${local.oidc_provider_id}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "app_sa_s3" {
  name = "${var.cluster_name}-app-sa-s3"
  role = aws_iam_role.app_sa.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:ListBucket"
      ]
      Resource = [
        "arn:${data.aws_partition.current.partition}:s3:::${var.app_bucket_name}",
        "arn:${data.aws_partition.current.partition}:s3:::${var.app_bucket_name}/*"
      ]
    }]
  })
}

# ── Node group IAM role ───────────────────────────────────────────────────────

resource "aws_iam_role" "node_group" {
  name = "${var.cluster_name}-node-group-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "node_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node_group.name
}

resource "aws_iam_role_policy_attachment" "node_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node_group.name
}

resource "aws_iam_role_policy_attachment" "node_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node_group.name
}

# ── Launch template — tags nodes with Environment (Task 1b) ──────────────────
# A launch template is required to propagate custom tags to EC2 instances
# because aws_eks_node_group.tags only tags the node group object, not the nodes.

resource "aws_launch_template" "nodes" {
  name_prefix   = "${var.cluster_name}-node-"
  instance_type = "t3.medium"

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Environment = var.environment
      ManagedBy   = "terraform"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(var.tags, {
      Environment = var.environment
      ManagedBy   = "terraform"
    })
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ── Managed node group (Task 1b: t3.medium, min 1, max 3) ────────────────────

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-nodes"
  node_role_arn   = aws_iam_role.node_group.arn
  subnet_ids      = var.node_group_subnet_ids

  # FIX (Bug 4): Instance type moved to launch template; scaling set to task spec
  # (min 1, max 3). The original had no instance_types and used wrong scaling values.
  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 3
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.node_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.node_AmazonEC2ContainerRegistryReadOnly,
  ]

  tags = var.tags
}
