################################################################################
# IAM Role and Policy for S3 Model Storage Access
################################################################################

# IAM role for model storage with EKS Pod Identity trust policy
resource "aws_iam_role" "model_storage_role" {
  name = "genai-model-storage-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })

  tags = merge(local.tags, {
    Name        = "genai-model-storage-role"
    Purpose     = "S3 access for model storage"
    Environment = "workshop"
    CostCenter  = "genai-workshop"
  })
}

# Custom IAM policy with minimum required S3 permissions
resource "aws_iam_policy" "model_storage_policy" {
  name        = "genai-model-storage-policy"
  description = "Policy for S3 model storage access with minimum required permissions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.model_storage.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.model_storage.arn
      }
    ]
  })

  tags = merge(local.tags, {
    Name        = "genai-model-storage-policy"
    Purpose     = "S3 access policy for model storage"
    Environment = "workshop"
    CostCenter  = "genai-workshop"
  })
}

# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "model_storage_policy_attachment" {
  role       = aws_iam_role.model_storage_role.name
  policy_arn = aws_iam_policy.model_storage_policy.arn
}

################################################################################
# IAM Policy for S3 CSI Driver (Node Group)
################################################################################

# IAM policy for S3 CSI driver to access the model storage bucket
resource "aws_iam_policy" "s3_csi_driver_policy" {
  name        = "genai-s3-csi-driver-policy"
  description = "Policy for S3 CSI driver to access model storage bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.model_storage.arn,
          "${aws_s3_bucket.model_storage.arn}/*"
        ]
      }
    ]
  })

  tags = merge(local.tags, {
    Name        = "genai-s3-csi-driver-policy"
    Purpose     = "S3 CSI driver access policy"
    Environment = "workshop"
    CostCenter  = "genai-workshop"
  })
}

################################################################################
# IAM Role for S3 CSI Driver Service Account
################################################################################

# IAM role for S3 CSI driver service account
resource "aws_iam_role" "s3_csi_driver_role" {
  name = "genai-s3-csi-driver-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })

  tags = merge(local.tags, {
    Name        = "genai-s3-csi-driver-role"
    Purpose     = "S3 CSI driver IAM role"
    Environment = "workshop"
    CostCenter  = "genai-workshop"
  })
}

################################################################################
# IAM Role for inference benchmarking
################################################################################

# IAM role for inference benchmarking
resource "aws_iam_role" "s3_inference_benchmarking" {
  name = "genai-inference-benchmarking-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })

  tags = merge(local.tags, {
    Name        = "genai-inference-benchmarking-role"
    Purpose     = "Inference benchmarking with S3 write access"
    Environment = "workshop"
    CostCenter  = "genai-workshop"
  })
}

# IAM policy for inference benchmarking with write access
resource "aws_iam_policy" "inference_benchmarking_policy" {
  name        = "genai-inference-benchmarking-policy"
  description = "Policy for inference benchmarking with S3 read/write access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          "${aws_s3_bucket.model_storage.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.model_storage.arn
      }
    ]
  })

  tags = merge(local.tags, {
    Name        = "genai-inference-benchmarking-policy"
    Purpose     = "Inference benchmarking S3 access policy"
    Environment = "workshop"
    CostCenter  = "genai-workshop"
  })
}


# Attach S3 policy to S3 CSI driver role
resource "aws_iam_role_policy_attachment" "s3_csi_driver_policy_attachment" {
  role       = aws_iam_role.s3_csi_driver_role.name
  policy_arn = aws_iam_policy.s3_csi_driver_policy.arn
}

# Attach inference benchmarking policy to inference benchmarking role
resource "aws_iam_role_policy_attachment" "inference_benchmarking_policy_attachment" {
  role       = aws_iam_role.s3_inference_benchmarking.name
  policy_arn = aws_iam_policy.inference_benchmarking_policy.arn
}

# Outputs moved to outputs.tf for better organization