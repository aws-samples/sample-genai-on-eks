################################################################################
# Amazon Managed Prometheus (AMP) Workspace
################################################################################

# Create AMP workspace
resource "aws_prometheus_workspace" "main" {
  alias = "${local.name}-amp-workspace"

  tags = merge(local.tags, {
    Name        = "${local.name}-amp-workspace"
    Purpose     = "Managed Prometheus for GenAI Workshop"
    Environment = "workshop"
    CostCenter  = "genai-workshop"
  })
}

################################################################################
# IAM Role and Policy for Prometheus Remote Write
################################################################################

# IAM role for Prometheus to remote write to AMP
resource "aws_iam_role" "prometheus_remote_write_role" {
  name = "${local.name}-prometheus-remote-write-role"

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
    Name        = "${local.name}-prometheus-remote-write-role"
    Purpose     = "Prometheus remote write to AMP"
    Environment = "workshop"
    CostCenter  = "genai-workshop"
  })
}

# IAM policy for Prometheus remote write
resource "aws_iam_policy" "prometheus_remote_write_policy" {
  name        = "${local.name}-prometheus-remote-write-policy"
  description = "Policy for Prometheus to remote write to AMP"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "aps:RemoteWrite"
        ]
        Resource = aws_prometheus_workspace.main.arn
      }
    ]
  })

  tags = merge(local.tags, {
    Name        = "${local.name}-prometheus-remote-write-policy"
    Purpose     = "Prometheus remote write policy"
    Environment = "workshop"
    CostCenter  = "genai-workshop"
  })
}

# Attach policy to Prometheus role
resource "aws_iam_role_policy_attachment" "prometheus_remote_write_attachment" {
  role       = aws_iam_role.prometheus_remote_write_role.name
  policy_arn = aws_iam_policy.prometheus_remote_write_policy.arn
}

################################################################################
# IAM Role and Policy for Grafana Query Access
################################################################################

# IAM role for Grafana to query AMP
resource "aws_iam_role" "grafana_query_role" {
  name = "${local.name}-grafana-query-role"

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
    Name        = "${local.name}-grafana-query-role"
    Purpose     = "Grafana query access to AMP"
    Environment = "workshop"
    CostCenter  = "genai-workshop"
  })
}

# IAM policy for Grafana query access
resource "aws_iam_policy" "grafana_query_policy" {
  name        = "${local.name}-grafana-query-policy"
  description = "Policy for Grafana to query AMP"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "aps:QueryMetrics",
          "aps:GetSeries",
          "aps:GetLabels",
          "aps:GetMetricMetadata",
          "aps:DescribeWorkspace",
          "aps:GetMetricMetadata"
        ]
        Resource = aws_prometheus_workspace.main.arn
      }
    ]
  })

  tags = merge(local.tags, {
    Name        = "${local.name}-grafana-query-policy"
    Purpose     = "Grafana query policy"
    Environment = "workshop"
    CostCenter  = "genai-workshop"
  })
}

# Attach policy to Grafana role
resource "aws_iam_role_policy_attachment" "grafana_query_attachment" {
  role       = aws_iam_role.grafana_query_role.name
  policy_arn = aws_iam_policy.grafana_query_policy.arn
}

################################################################################
# Kubernetes Service Accounts
################################################################################

# Create monitoring namespace first
resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = "monitoring"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  depends_on = [
    module.eks,
    module.eks.cluster_addons
  ]
}

# Service account for Prometheus
resource "kubectl_manifest" "prometheus_service_account" {
  depends_on = [
    kubernetes_namespace_v1.monitoring
  ]

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ServiceAccount"
    metadata = {
      name      = "prometheus-sa"
      namespace = "monitoring"
      labels = {
        "app.kubernetes.io/name"       = "prometheus"
        "app.kubernetes.io/component"  = "service-account"
        "app.kubernetes.io/managed-by" = "terraform"
      }
    }
  })
}

# Service account for Grafana
resource "kubectl_manifest" "grafana_service_account" {
  depends_on = [
    kubernetes_namespace_v1.monitoring
  ]

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ServiceAccount"
    metadata = {
      name      = "grafana-sa"
      namespace = "monitoring"
      labels = {
        "app.kubernetes.io/name"       = "grafana"
        "app.kubernetes.io/component"  = "service-account"
        "app.kubernetes.io/managed-by" = "terraform"
      }
    }
  })
}

################################################################################
# EKS Pod Identity Associations
################################################################################

# Pod Identity association for Prometheus
resource "aws_eks_pod_identity_association" "prometheus" {
  cluster_name    = module.eks.cluster_name
  namespace       = "monitoring"
  service_account = "prometheus-sa"
  role_arn        = aws_iam_role.prometheus_remote_write_role.arn

  tags = merge(local.tags, {
    Name        = "${local.name}-prometheus-pod-identity"
    Purpose     = "Pod Identity for Prometheus remote write"
    Environment = "workshop"
    CostCenter  = "genai-workshop"
  })

  depends_on = [
    kubectl_manifest.prometheus_service_account,
    module.eks.cluster_addons
  ]
}

# Pod Identity association for Grafana
resource "aws_eks_pod_identity_association" "grafana" {
  cluster_name    = module.eks.cluster_name
  namespace       = "monitoring"
  service_account = "grafana-sa"
  role_arn        = aws_iam_role.grafana_query_role.arn

  tags = merge(local.tags, {
    Name        = "${local.name}-grafana-pod-identity"
    Purpose     = "Pod Identity for Grafana query access"
    Environment = "workshop"
    CostCenter  = "genai-workshop"
  })

  depends_on = [
    kubectl_manifest.grafana_service_account,
    module.eks.cluster_addons
  ]
}
