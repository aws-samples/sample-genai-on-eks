################################################################################
# Kubernetes Service Account for Model Storage
################################################################################

# Kubernetes service account for model storage using kubectl_manifest
resource "kubectl_manifest" "model_storage_service_account" {
  depends_on = [
    module.eks,
    module.eks.cluster_addons
  ]

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ServiceAccount"
    metadata = {
      name      = "model-storage-sa"
      namespace = "default"
      labels = {
        "app.kubernetes.io/name"       = "model-storage"
        "app.kubernetes.io/component"  = "service-account"
        "app.kubernetes.io/managed-by" = "terraform"
      }
    }
  })
}

################################################################################
# EKS Pod Identity Association for Model Storage
################################################################################

# EKS Pod Identity association linking service account to IAM role
resource "aws_eks_pod_identity_association" "model_storage" {
  cluster_name    = module.eks.cluster_name
  namespace       = "default"
  service_account = "model-storage-sa"
  role_arn        = aws_iam_role.model_storage_role.arn

  tags = merge(local.tags, {
    Name        = "model-storage-pod-identity"
    Purpose     = "Pod Identity association for model storage"
    Environment = "workshop"
    CostCenter  = "genai-workshop"
  })

  depends_on = [
    kubectl_manifest.model_storage_service_account,
    module.eks.cluster_addons
  ]
}

################################################################################
# EKS Pod Identity Association for S3 CSI Driver
################################################################################

# EKS Pod Identity association for S3 CSI driver service account
resource "aws_eks_pod_identity_association" "s3_csi_driver" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "s3-csi-driver-sa"
  role_arn        = aws_iam_role.s3_csi_driver_role.arn

  tags = merge(local.tags, {
    Name        = "s3-csi-driver-pod-identity"
    Purpose     = "Pod Identity association for S3 CSI driver"
    Environment = "workshop"
    CostCenter  = "genai-workshop"
  })

  depends_on = [
    module.eks,
    module.eks.cluster_addons
  ]
}



################################################################################
# EKS Pod Identity Association for inference benchmarking
# This should match the default values in our chart
# https://github.com/awslabs/ai-on-eks-charts/blob/main/charts/benchmark-charts/values.yaml
################################################################################

resource "aws_eks_pod_identity_association" "s3_inference_benchmarking" {
  cluster_name    = module.eks.cluster_name
  namespace       = "benchmarking"
  service_account = "inference-perf-sa"
  role_arn        = aws_iam_role.s3_inference_benchmarking.arn

  tags = merge(local.tags, {
    Name        = "inference-benchmarking-pod-identity"
    Purpose     = "Pod Identity association for inference benchmarking"
    Environment = "workshop"
    CostCenter  = "genai-workshop"
  })

  depends_on = [
    module.eks,
    module.eks.cluster_addons
  ]
}
