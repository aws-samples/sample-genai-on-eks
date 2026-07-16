################################################################################
# Variables for GenAI Workshop Infrastructure
################################################################################

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "genai-workshop"
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.34"
}

variable "region" {
  description = "AWS region for resources"
  type        = string
  default     = null # Will use current region from data source
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use single NAT Gateway for cost optimization"
  type        = bool
  default     = true
}

variable "s3_bucket_prefix" {
  description = "Prefix for S3 bucket name (will be suffixed with account ID)"
  type        = string
  default     = "genai-models"
}

variable "model_storage_size" {
  description = "Size of the model storage PV"
  type        = string
  default     = "20Gi"
}

variable "model_prefix" {
  description = "S3 prefix for model files"
  type        = string
  default     = "Ministral-3-8B-Instruct-2512/"
}

variable "gpu_instance_types" {
  description = "Instance types for GPU nodes (ordered by preference for ODCR failover)"
  type        = list(string)
  default     = ["g6e.2xlarge", "g6e.4xlarge", "g6e.8xlarge"]
}

variable "ingress_inbound_cidrs" {
  description = "Allowed inbound CIDRs for Ingress resources"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "grafana_admin_password" {
  description = "Admin password for Grafana"
  type        = string
  default     = "notforproductionuse"
  sensitive   = true
}


