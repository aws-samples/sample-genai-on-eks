################################################################################
# EKS Auto Mode Cluster
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.19.0"

  name               = local.name
  kubernetes_version = var.cluster_version

  iam_role_use_name_prefix = true
  iam_role_name            = "${local.name}-eks-cluster-role"

  node_iam_role_use_name_prefix = true
  node_iam_role_name            = "${local.name}-eks-node-role"

  enable_cluster_creator_admin_permissions = true

  addons = {
    metrics-server = {
      before_compute = true
      most_recent    = true
    }
  }

  # Network configuration
  vpc_id                  = module.vpc.vpc_id
  subnet_ids              = module.vpc.private_subnets
  endpoint_private_access = true
  endpoint_public_access  = true

  # EKS Auto Mode configuration
  compute_config = {
    enabled    = true
    node_pools = ["general-purpose", "system"]
  }

  tags = local.tags
}

################################################################################
# S3 CSI Driver Addon
################################################################################

data "aws_eks_addon_version" "s3_csi_driver" {
  addon_name         = "aws-mountpoint-s3-csi-driver"
  kubernetes_version = module.eks.cluster_version
  most_recent        = true
}

resource "aws_eks_addon" "s3_csi_driver" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "aws-mountpoint-s3-csi-driver"
  addon_version               = data.aws_eks_addon_version.s3_csi_driver.version
  service_account_role_arn    = aws_iam_role.s3_csi_driver_role.arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = merge(local.tags, {
    Name        = "genai-s3-csi-driver-addon"
    Purpose     = "S3 CSI driver addon"
    Environment = "workshop"
    CostCenter  = "genai-workshop"
  })

  depends_on = [
    module.eks,
    aws_iam_role.s3_csi_driver_role,
    aws_iam_role_policy_attachment.s3_csi_driver_policy_attachment
  ]
}
