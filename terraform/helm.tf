################################################################################
# Observability Stack (Kube Prometheus Stack + Grafana Operator)
################################################################################

locals {
  amp_datasource_name = "Amazon-Managed-Prometheus"

  dashboards = {
    vllm = replace(replace(
      file("${path.module}/grafana-dashboards/vllm-dashboard.json"),
      "\"type\": \"prometheus\"", "\"type\": \"grafana-amazonprometheus-datasource\""),
      "\"uid\": \"prometheus\"", "\"uid\": \"${local.amp_datasource_name}\""
    )
    ray_default = replace(replace(
      file("${path.module}/grafana-dashboards/ray-default-grafana-dashboard.json"),
      "\"type\": \"prometheus\"", "\"type\": \"grafana-amazonprometheus-datasource\""),
      "\"uid\": \"prometheus\"", "\"uid\": \"${local.amp_datasource_name}\""
    )
    ray_serve = replace(replace(
      file("${path.module}/grafana-dashboards/ray-serve-grafana-dashboard.json"),
      "\"type\": \"prometheus\"", "\"type\": \"grafana-amazonprometheus-datasource\""),
      "\"uid\": \"prometheus\"", "\"uid\": \"${local.amp_datasource_name}\""
    )
    ray_serve_deployment = replace(replace(
      file("${path.module}/grafana-dashboards/ray-serve-deployment-grafana-dashboard.json"),
      "\"type\": \"prometheus\"", "\"type\": \"grafana-amazonprometheus-datasource\""),
      "\"uid\": \"prometheus\"", "\"uid\": \"${local.amp_datasource_name}\""
    )
    dcgm = replace(replace(
      file("${path.module}/grafana-dashboards/dcgm-grafana-dashboard.json"),
      "\"type\": \"prometheus\"", "\"type\": \"grafana-amazonprometheus-datasource\""),
      "\"uid\": \"prometheus\"", "\"uid\": \"${local.amp_datasource_name}\""
    )
  }
}

resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "69.8.2"
  namespace        = "monitoring"
  create_namespace = false
  wait             = false

  values = [
    <<-EOT
    alertmanager:
      enabled: false
    
    grafana:
      enabled: true
      defaultDashboardsEnabled: true
      defaultDashboardsTimezone: utc
      adminPassword: "notforproductionuse"
      service:
        type: ClusterIP
        port: 3000
      # Use the service account with AMP query permissions
      serviceAccount:
        create: false
        name: grafana-sa
      # Configure Grafana to run on system node pool
      nodeSelector:
        karpenter.sh/nodepool: system
      tolerations:
        - key: CriticalAddonsOnly
          operator: Exists
          effect: NoSchedule
      # Configure AWS authentication
      grafana.ini:
        auth:
          sigv4_auth_enabled: true
      # Disable default Prometheus datasource since we're using AMP
      sidecar:
        datasources:
          defaultDatasourceEnabled: false
      # Install AWS data source plugins
      plugins:
        - grafana-amazonprometheus-datasource ${var.grafana_amp_plugin_version}
      # Add AMP as a datasource using the dedicated AMP plugin
      additionalDataSources:
        - name: Amazon-Managed-Prometheus
          type: grafana-amazonprometheus-datasource
          access: proxy
          url: ${trimsuffix(aws_prometheus_workspace.main.prometheus_endpoint, "/")}
          isDefault: true
          jsonData:
            sigV4Auth: true
            defaultRegion: ${local.region}
            sigV4Region: ${local.region}
          editable: true
    
    prometheus:
      serviceAccount:
        create: false
        name: prometheus-sa
      prometheusSpec:
        serviceMonitorSelectorNilUsesHelmValues: false
        # Use the service account with AMP remote write permissions
        serviceAccountName: prometheus-sa
        # Configure remote write to Amazon Managed Prometheus
        remoteWrite:
          - url: ${aws_prometheus_workspace.main.prometheus_endpoint}api/v1/remote_write
            sigv4:
              region: ${local.region}
            queueConfig:
              maxSamplesPerSend: 1000
              maxShards: 200
              capacity: 2500
        # Configure Prometheus to run on system node pool
        nodeSelector:
          karpenter.sh/nodepool: system
        tolerations:
          - key: CriticalAddonsOnly
            operator: Exists
            effect: NoSchedule

    # Configure Prometheus Operator to run on system node pool
    prometheusOperator:
      nodeSelector:
        karpenter.sh/nodepool: system
      tolerations:
        - key: CriticalAddonsOnly
          operator: Exists
          effect: NoSchedule

    # Configure kube-state-metrics to run on system node pool
    kube-state-metrics:
      nodeSelector:
        karpenter.sh/nodepool: system
      tolerations:
        - key: CriticalAddonsOnly
          operator: Exists
          effect: NoSchedule

    # Configure node-exporter (runs on all nodes by default)
    nodeExporter:
      tolerations:
        - key: CriticalAddonsOnly
          operator: Exists
          effect: NoSchedule
    EOT
  ]

  depends_on = [
    module.eks,
    kubernetes_namespace_v1.monitoring,
    aws_prometheus_workspace.main,
    aws_eks_pod_identity_association.prometheus,
    aws_eks_pod_identity_association.grafana
  ]
}

resource "helm_release" "grafana_operator" {
  name       = "grafana-operator"
  namespace  = "monitoring"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana-operator"
  version    = "5.22.2"
  wait       = false

  values = [
    <<-EOT
    # Configure Grafana Operator to run on system node pool
    nodeSelector:
      karpenter.sh/nodepool: system
    tolerations:
      - key: CriticalAddonsOnly
        operator: Exists
        effect: NoSchedule

    # Also configure the operator deployment specifically
    deployment:
      nodeSelector:
        karpenter.sh/nodepool: system
      tolerations:
        - key: CriticalAddonsOnly
          operator: Exists
          effect: NoSchedule

    # Configure the operator container settings
    operator:
      scanAllNamespaces: true
    EOT
  ]

  depends_on = [module.eks, helm_release.kube_prometheus_stack]
}


resource "kubectl_manifest" "grafana_admin_credentials" {
  depends_on = [
    module.eks,
    module.eks.cluster_addons,
    helm_release.grafana_operator,
    helm_release.kube_prometheus_stack
  ]

  server_side_apply = true
  yaml_body         = <<-YAML
    apiVersion: v1
    kind: Secret
    metadata:
      name: grafana-admin-credentials
      namespace: monitoring
    data:
      admin-user: ${base64encode("admin")}
      admin-password: ${base64encode(var.grafana_admin_password)}
  YAML
}


resource "kubectl_manifest" "external_grafana" {
  depends_on = [
    module.eks,
    module.eks.cluster_addons,
    helm_release.grafana_operator,
    kubectl_manifest.grafana_admin_credentials,
    helm_release.kube_prometheus_stack
  ]

  server_side_apply = true
  yaml_body         = <<-YAML
    apiVersion: grafana.integreatly.org/v1beta1
    kind: Grafana
    metadata:
      name: external-grafana
      namespace: monitoring
      labels:
        dashboards: external-grafana
    spec:
      external:
        url: http://kube-prometheus-stack-grafana.monitoring.svc.cluster.local:3000
        adminUser:
          name: grafana-admin-credentials
          key: admin-user
        adminPassword:
          name: grafana-admin-credentials
          key: admin-password
  YAML
}

resource "kubectl_manifest" "vllm_grafana_dashboard_config" {
  depends_on = [
    module.eks,
    module.eks.cluster_addons,
    helm_release.kube_prometheus_stack
  ]

  server_side_apply = true
  yaml_body         = <<-YAML
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: vllm-grafana-dashboard-config
      namespace: monitoring
    data:
      vllm-dashboard.json: ${jsonencode(local.dashboards.vllm)}
  YAML
}

resource "kubectl_manifest" "vllm_ray_grafana_dashboard_config" {
  server_side_apply = true
  yaml_body         = <<-YAML
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: vllm-ray-grafana-dashboard-config
      namespace: monitoring
    data:
      vllm-ray-dashboard.json: ${jsonencode(file("${path.module}/grafana-dashboards/vllm-ray-dashboard.json"))}
  YAML

  depends_on = [module.eks, helm_release.kube_prometheus_stack]
}

resource "kubectl_manifest" "ray_default_grafana_dashboard_config" {
  depends_on = [
    module.eks,
    module.eks.cluster_addons,
    helm_release.kube_prometheus_stack
  ]

  server_side_apply = true
  yaml_body         = <<-YAML
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: ray-grafana-default-dashboard-config
      namespace: monitoring
    data:
      ray-default-grafana-dashboard.json: ${jsonencode(local.dashboards.ray_default)}
  YAML
}

resource "kubectl_manifest" "ray_serve_grafana_dashboard_config" {
  depends_on = [
    module.eks,
    module.eks.cluster_addons,
    helm_release.kube_prometheus_stack
  ]

  server_side_apply = true
  yaml_body         = <<-YAML
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: ray-grafana-serve-dashboard-config
      namespace: monitoring
    data:
      ray-serve-grafana-dashboard.json: ${jsonencode(local.dashboards.ray_serve)}
  YAML
}

resource "kubectl_manifest" "ray_serve_deployment_grafana_dashboard_config" {
  depends_on = [
    module.eks,
    module.eks.cluster_addons,
    helm_release.kube_prometheus_stack
  ]

  server_side_apply = true
  yaml_body         = <<-YAML
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: ray-grafana-serve-deployment-dashboard-config
      namespace: monitoring
    data:
      ray-serve-deployment-grafana-dashboard.json: ${jsonencode(local.dashboards.ray_serve_deployment)}
  YAML
}

resource "kubectl_manifest" "dcgm_grafana_dashboard_config" {
  depends_on = [
    module.eks,
    module.eks.cluster_addons,
    helm_release.kube_prometheus_stack
  ]

  server_side_apply = true
  yaml_body         = <<-YAML
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: dcgm-dashboard-config
      namespace: monitoring
    data:
      dcgm-grafana-dashboard.json: ${jsonencode(local.dashboards.dcgm)}
  YAML
}

resource "kubectl_manifest" "patch_dashboards_job" {
  depends_on = [helm_release.kube_prometheus_stack]

  yaml_body = <<-YAML
    apiVersion: batch/v1
    kind: Job
    metadata:
      name: patch-grafana-dashboards
      namespace: monitoring
    spec:
      ttlSecondsAfterFinished: 300
      template:
        spec:
          serviceAccountName: patch-dashboards-sa
          restartPolicy: OnFailure
          containers:
          - name: patch
            image: bitnami/kubectl:latest
            command:
            - /bin/bash
            - -c
            - |
              sleep 30
              kubectl get configmap -n monitoring -l grafana_dashboard=1 -o name | while read cm; do
                kubectl get $cm -n monitoring -o json | \
                  jq '.data |= with_entries(.value |= (fromjson | walk(if type == "object" and has("datasource") then .datasource = (if .datasource | type == "object" then .datasource | .type = "grafana-amazonprometheus-datasource" | .uid = "${local.amp_datasource_name}" elif .datasource == "prometheus" or .datasource == "$${DS_PROMETHEUS}" then {"type": "grafana-amazonprometheus-datasource", "uid": "${local.amp_datasource_name}"} else .datasource end) else . end) | tostring))' | \
                  kubectl apply -f -
              done
              kubectl rollout restart deployment/kube-prometheus-stack-grafana -n monitoring
  YAML
}

resource "kubectl_manifest" "patch_dashboards_sa" {
  depends_on = [kubernetes_namespace_v1.monitoring]

  yaml_body = <<-YAML
    apiVersion: v1
    kind: ServiceAccount
    metadata:
      name: patch-dashboards-sa
      namespace: monitoring
  YAML
}

resource "kubectl_manifest" "patch_dashboards_role" {
  depends_on = [kubernetes_namespace_v1.monitoring]

  yaml_body = <<-YAML
    apiVersion: rbac.authorization.k8s.io/v1
    kind: Role
    metadata:
      name: patch-dashboards-role
      namespace: monitoring
    rules:
    - apiGroups: [""]
      resources: ["configmaps"]
      verbs: ["get", "list", "patch", "update"]
    - apiGroups: ["apps"]
      resources: ["deployments"]
      verbs: ["get", "patch"]
  YAML
}

resource "kubectl_manifest" "patch_dashboards_rolebinding" {
  depends_on = [
    kubectl_manifest.patch_dashboards_sa,
    kubectl_manifest.patch_dashboards_role
  ]

  yaml_body = <<-YAML
    apiVersion: rbac.authorization.k8s.io/v1
    kind: RoleBinding
    metadata:
      name: patch-dashboards-rolebinding
      namespace: monitoring
    roleRef:
      apiGroup: rbac.authorization.k8s.io
      kind: Role
      name: patch-dashboards-role
    subjects:
    - kind: ServiceAccount
      name: patch-dashboards-sa
      namespace: monitoring
  YAML
}

################################################################################
# GrafanaDashboard CRDs - Register dashboards with Grafana Operator
################################################################################

resource "kubectl_manifest" "vllm_grafana_dashboard" {
  depends_on = [
    kubectl_manifest.external_grafana,
    kubectl_manifest.vllm_grafana_dashboard_config
  ]

  server_side_apply = true
  yaml_body         = <<-YAML
    apiVersion: grafana.integreatly.org/v1beta1
    kind: GrafanaDashboard
    metadata:
      name: vllm-dashboard
      namespace: monitoring
      labels:
        dashboards: "external-grafana"
    spec:
      instanceSelector:
        matchLabels:
          dashboards: external-grafana
      configMapRef:
        name: vllm-grafana-dashboard-config
        key: vllm-dashboard.json
  YAML
}

resource "kubectl_manifest" "vllm_ray_grafana_dashboard" {
  depends_on = [
    kubectl_manifest.external_grafana,
    kubectl_manifest.vllm_ray_grafana_dashboard_config
  ]

  server_side_apply = true
  yaml_body         = <<-YAML
    apiVersion: grafana.integreatly.org/v1beta1
    kind: GrafanaDashboard
    metadata:
      name: vllm-ray-grafana-dashboard
      namespace: monitoring
      labels:
        dashboards: "external-grafana"
    spec:
      instanceSelector:
        matchLabels:
          dashboards: external-grafana
      configMapRef:
        name: vllm-ray-grafana-dashboard-config
        key: vllm-ray-dashboard.json
  YAML
}

resource "kubectl_manifest" "ray_default_grafana_dashboard" {
  depends_on = [
    kubectl_manifest.external_grafana,
    kubectl_manifest.ray_default_grafana_dashboard_config
  ]

  server_side_apply = true
  yaml_body         = <<-YAML
    apiVersion: grafana.integreatly.org/v1beta1
    kind: GrafanaDashboard
    metadata:
      name: ray-grafana-default-dashboard
      namespace: monitoring
      labels:
        dashboards: "external-grafana"
    spec:
      instanceSelector:
        matchLabels:
          dashboards: external-grafana
      configMapRef:
        name: ray-grafana-default-dashboard-config
        key: ray-default-grafana-dashboard.json
  YAML
}

resource "kubectl_manifest" "ray_serve_grafana_dashboard" {
  depends_on = [
    kubectl_manifest.external_grafana,
    kubectl_manifest.ray_serve_grafana_dashboard_config
  ]

  server_side_apply = true
  yaml_body         = <<-YAML
    apiVersion: grafana.integreatly.org/v1beta1
    kind: GrafanaDashboard
    metadata:
      name: ray-grafana-serve-dashboard
      namespace: monitoring
      labels:
        dashboards: "external-grafana"
    spec:
      instanceSelector:
        matchLabels:
          dashboards: external-grafana
      configMapRef:
        name: ray-grafana-serve-dashboard-config
        key: ray-serve-grafana-dashboard.json
  YAML
}

resource "kubectl_manifest" "ray_serve_deployment_grafana_dashboard" {
  depends_on = [
    kubectl_manifest.external_grafana,
    kubectl_manifest.ray_serve_deployment_grafana_dashboard_config
  ]

  server_side_apply = true
  yaml_body         = <<-YAML
    apiVersion: grafana.integreatly.org/v1beta1
    kind: GrafanaDashboard
    metadata:
      name: ray-grafana-serve-deployment-dashboard
      namespace: monitoring
      labels:
        dashboards: "external-grafana"
    spec:
      instanceSelector:
        matchLabels:
          dashboards: external-grafana
      configMapRef:
        name: ray-grafana-serve-deployment-dashboard-config
        key: ray-serve-deployment-grafana-dashboard.json
  YAML
}

resource "kubectl_manifest" "dcgm_grafana_dashboard" {
  depends_on = [
    kubectl_manifest.external_grafana,
    kubectl_manifest.dcgm_grafana_dashboard_config
  ]

  server_side_apply = true
  yaml_body         = <<-YAML
    apiVersion: grafana.integreatly.org/v1beta1
    kind: GrafanaDashboard
    metadata:
      name: dcgm-grafana-dashboard
      namespace: monitoring
      labels:
        dashboards: "external-grafana"
    spec:
      instanceSelector:
        matchLabels:
          dashboards: external-grafana
      configMapRef:
        name: dcgm-dashboard-config
        key: dcgm-grafana-dashboard.json
  YAML
}
