
################################################################################
# GenAI Workshop Infrastructure - Main Configuration
################################################################################

# Data sources for current AWS context
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# EKS cluster authentication data source
data "aws_eks_cluster_auth" "main" {
  name = module.eks.cluster_name
}

data "aws_availability_zones" "available" {
  # Do not include local zones
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
  # https://docs.aws.amazon.com/eks/latest/userguide/network-reqs.html#network-requirements-subnets
  exclude_zone_ids = ["use1-az3", "usw1-az2", "cac1-az3"]
}

# Local values for consistent naming and configuration
locals {
  name   = var.cluster_name
  region = var.region != null ? var.region : data.aws_region.current.id

  # Keep tags minimal to avoid unnecessary resource updates
  tags = {}

  # VPC configuration
  vpc_cidr = var.vpc_cidr
  azs      = data.aws_availability_zones.available.names

  # S3 bucket name with account ID for uniqueness
  s3_bucket_name = "${var.s3_bucket_prefix}-${data.aws_caller_identity.current.account_id}"
}

################################################################################
# Provider Configuration
################################################################################

provider "aws" {
  alias  = "virginia"
  region = "us-east-1"
}


provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", data.aws_eks_cluster_auth.main.name]
      command     = "aws"
    }
  }
}

provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }

}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", data.aws_eks_cluster_auth.main.name]
    command     = "aws"
  }
}
