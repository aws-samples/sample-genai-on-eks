# GenAI on EKS Workshop - Terraform Infrastructure

> Deploy the [GenAI on EKS Workshop](https://catalog.workshops.aws/genai-on-eks) infrastructure to your own AWS account using Terraform. This sets up a production-ready EKS cluster with GPU support, observability, and model storage — everything you need to run the workshop labs.

## Architecture

![GenAI on EKS Workshop Architecture](../architecture.png)

The Terraform configuration deploys:

- **Amazon EKS Auto Mode** cluster (Kubernetes 1.34) with system and general-purpose node pools
- **Amazon Managed Prometheus (AMP)** workspace for metrics collection
- **Grafana** with pre-built dashboards for vLLM, Ray Serve, and DCGM GPU metrics
- **S3 bucket** (`genai-models-<account-id>`) for model storage via Mountpoint S3 CSI driver
- **VPC** with public/private subnets across multiple AZs
- **IAM roles and Pod Identity** associations for secure workload access
- **kube-prometheus-stack** for cluster observability with remote write to AMP

---

## Prerequisites

| Tool | Version | Install |
| ---- | ------- | ------- |
| AWS CLI | >= 2.x | [Guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) |
| Terraform | >= 1.3 | [Guide](https://developer.hashicorp.com/terraform/install) |
| kubectl | latest | [Guide](https://kubernetes.io/docs/tasks/tools/) |

Ensure your AWS credentials are configured:

```bash
aws sts get-caller-identity
```

---

## Quick Start

### 1. Clone the repo

```bash
git clone https://github.com/aws-samples/sample-genai-on-eks.git
cd sample-genai-on-eks/terraform
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Deploy the infrastructure

Deploy with the default region (`us-east-2`):

```bash
terraform apply
```

Or deploy to a different region:

```bash
terraform apply -var="region=us-west-2"
```

> Deployment takes approximately 20-25 minutes.

### 4. Configure kubectl

```bash
aws eks update-kubeconfig --name genai-workshop --region us-east-2
```

If you deployed to a different region, replace `us-east-2` with your chosen region.

---

## Configuration

All variables have sensible defaults. Override any of them with `-var` flags:

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `region` | `us-east-2` | AWS region for all resources |
| `cluster_name` | `genai-workshop` | Name of the EKS cluster |
| `cluster_version` | `1.34` | Kubernetes version |
| `vpc_cidr` | `10.0.0.0/16` | CIDR block for the VPC |
| `gpu_instance_types` | `["g6e.2xlarge"]` | Instance types for GPU nodes |
| `s3_bucket_prefix` | `genai-models` | Prefix for the S3 model storage bucket |
| `grafana_admin_password` | `notforproductionuse` | Grafana admin password |

Example with multiple overrides:

```bash
terraform apply \
  -var="region=eu-west-1" \
  -var="cluster_name=my-genai-cluster" \
  -var="gpu_instance_types=[\"g5.2xlarge\"]"
```

---

## What Gets Deployed

| Component | Purpose |
| --------- | ------- |
| EKS Auto Mode Cluster | Managed Kubernetes with automatic node provisioning |
| VPC (3 AZs) | Networking with public/private subnets and NAT gateway |
| S3 Bucket + CSI Driver | Model storage accessible from pods via Mountpoint S3 |
| Amazon Managed Prometheus | Metrics backend for Grafana dashboards |
| kube-prometheus-stack | Prometheus, Grafana, and exporters |
| Grafana Dashboards | Pre-configured dashboards for vLLM, Ray Serve, DCGM |
| IAM Roles + Pod Identity | Secure access for Prometheus, Grafana, and model storage |
| ALB Ingress | Load balancer for exposing services |

---

## Accessing Services

**Grafana:**

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
```

Then open http://localhost:3000 (user: `admin`, password: `notforproductionuse`)

---

## Cleanup

To destroy all resources and avoid ongoing AWS charges:

```bash
terraform destroy
```

Or if you deployed to a custom region:

```bash
terraform destroy -var="region=us-west-2"
```

> The S3 bucket has `force_destroy = true` so it will be deleted even if it contains model files.

---

## Troubleshooting

| Issue | Solution |
| ----- | -------- |
| Timeout during apply | Re-run `terraform apply` — some resources take time to stabilize |
| kubectl auth errors | Run `aws eks update-kubeconfig` again with the correct region |
| GPU nodes not launching | Verify your account has quota for the GPU instance type in your region |
| Grafana shows no data | Wait 2-3 minutes for Prometheus to start scraping and remote writing |
