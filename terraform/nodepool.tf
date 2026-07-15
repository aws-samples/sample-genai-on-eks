################################################################################
# EKS Auto Mode NodeClass - GPU (Custom for higher IOPS needed by SOCI)
################################################################################

resource "kubectl_manifest" "eks_node_class_gpu" {
  depends_on = [
    module.eks,
    module.eks.cluster_addons
  ]

  # Wait for full removal on destroy so that all NodeClaims and their
  # underlying EC2 instances are terminated before Terraform proceeds
  # to tear down the EKS cluster and VPC networking.
  wait = true

  yaml_body = <<-YAML
    apiVersion: eks.amazonaws.com/v1
    kind: NodeClass
    metadata:
      name: gpu
    spec:
      # IAM role for EC2 instances
      role: ${module.eks.node_iam_role_name}
      
      # Subnet selection for GPU nodes (use private subnets)
      subnetSelectorTerms:
        - tags:
            kubernetes.io/role/internal-elb: "1"
      
      # Security group selection (use EKS cluster security groups)
      securityGroupSelectorTerms:
        - tags:
            aws:eks:cluster-name: ${module.eks.cluster_name}
      
      # Additional tags for GPU nodes
      tags:
        intent: gpu
        workload-type: gpu-intensive
        cluster: ${module.eks.cluster_name}
  YAML
}

################################################################################
# EKS Auto Mode Node Pool - GPU
################################################################################

resource "kubectl_manifest" "karpenter_node_pool_gpu" {
  depends_on = [
    module.eks,
    module.eks.cluster_addons,
    kubectl_manifest.eks_node_class_gpu
  ]

  # Wait for full removal on destroy so that Karpenter's termination
  # finalizer drains and terminates all EC2 instances before Terraform
  # proceeds to delete the NodeClass, EKS cluster, and VPC.
  wait = true

  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: gpu
    spec:
      template:
        metadata:
          labels:
            intent: gpu
            nvidia.com/gpu.present: "true"
        spec:
          nodeClassRef:
            group: eks.amazonaws.com
            kind: NodeClass
            name: gpu
          
          taints:
            - key: nvidia.com/gpu
              value: "true"
              effect: NoSchedule

          requirements:
            - key: kubernetes.io/arch
              operator: In
              values: ["amd64"]
            - key: kubernetes.io/os
              operator: In
              values: ["linux"]
            - key: karpenter.sh/capacity-type
              operator: In
              values: ["reserved", "on-demand"]
            - key: node.kubernetes.io/instance-type
              operator: In
              values: ${jsonencode(var.gpu_instance_types)}
      
      limits:
        cpu: 32
        nvidia.com/gpu: 1
      disruption:
        consolidationPolicy: WhenEmpty
        consolidateAfter: 900s
  YAML
}

