################################################################################
# Kubernetes S3 CSI Storage Resources using kubectl provider
################################################################################

# Create S3 prefix/folder to ensure it exists for S3 CSI driver
resource "aws_s3_object" "model_prefix" {
  bucket = aws_s3_bucket.model_storage.bucket
  key    = var.model_prefix
  source = "/dev/null"

  tags = merge(local.tags, {
    Name        = "genai-s3-prefix"
    Purpose     = "S3 prefix"
    Environment = "workshop"
    CostCenter  = "genai-workshop"

  })
}

# PersistentVolume for S3 model storage
resource "kubectl_manifest" "mistral_model_pv" {
  depends_on = [
    module.eks,
    module.eks.cluster_addons,
    aws_s3_bucket.model_storage,
    aws_s3_object.model_prefix
  ]

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "PersistentVolume"
    metadata = {
      name = "mistral-model-pv"
      labels = {
        "app.kubernetes.io/name"      = "mistral-model-storage"
        "app.kubernetes.io/component" = "storage"
      }
    }
    spec = {
      capacity = {
        storage = var.model_storage_size
      }
      accessModes                   = ["ReadOnlyMany"]
      persistentVolumeReclaimPolicy = "Retain"
      csi = {
        driver       = "s3.csi.aws.com"
        volumeHandle = "s3-csi-driver-volume"
        volumeAttributes = {
          bucketName = aws_s3_bucket.model_storage.bucket
          prefix     = var.model_prefix
          region     = local.region
        }
      }
    }
  })
}

# PersistentVolumeClaim for model access
resource "kubectl_manifest" "mistral_model_pvc" {
  depends_on = [
    module.eks,
    module.eks.cluster_addons,
    kubectl_manifest.mistral_model_pv
  ]

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "PersistentVolumeClaim"
    metadata = {
      name      = "mistral-model-pvc"
      namespace = "default"
      labels = {
        "app.kubernetes.io/name"      = "mistral-model-storage"
        "app.kubernetes.io/component" = "storage"
      }
    }
    spec = {
      accessModes = ["ReadOnlyMany"]
      volumeName  = "mistral-model-pv"
      resources = {
        requests = {
          storage = var.model_storage_size
        }
      }
    }
  })
}
