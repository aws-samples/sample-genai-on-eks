# GenAI on EKS Workshop - Terraform Infrastructure

> Deploy the [GenAI on EKS Workshop](https://catalog.workshops.aws/genai-on-eks) infrastructure to your own AWS account using Terraform. This sets up a production-ready EKS cluster with GPU support, observability, and model storage — everything you need to run the workshop labs.

## Architecture

![GenAI on EKS Workshop Architecture](https://raw.githubusercontent.com/aws-samples/sample-genai-on-eks/main/architecture.png)

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

| Tool      | Version | Install                                                                                |
| --------- | ------- | -------------------------------------------------------------------------------------- |
| AWS CLI   | >= 2.x  | [Guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) |
| Terraform | >= 1.3  | [Guide](https://developer.hashicorp.com/terraform/install)                             |
| kubectl   | latest  | [Guide](https://kubernetes.io/docs/tasks/tools/)                                       |

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
terraform apply --auto-approve
```

Or deploy to a different region:

```bash
terraform apply --auto-approve -var="region=us-west-2"
```

> Deployment takes approximately 20-25 minutes.

### 4. Configure kubectl

```bash
aws eks update-kubeconfig --name genai-workshop --region us-east-2
```

If you deployed to a different region, replace `us-east-2` with your chosen region.

### 5. Restrict ingress to your IP

Lock down ALB ingress to only allow traffic from your current public IP:

```bash
kubectl patch ingressclassparams alb --type=merge -p "{\"spec\":{\"inboundCIDRs\":[\"$(curl -s https://checkip.amazonaws.com | tr -d '\n')/32\"]}}"
```

### 6. Create On-Demand Capacity Reservation (ODCR)

Follow the steps here to create an ODCR for GPU instances: [Create ODCR](https://catalog.workshops.aws/genai-on-eks/en-US/50-getting-started/01-self-paced)

### 7. Follow the Workshop

Once you have the ODCR, you can follow along with the workshop labs: [Workshop Instructions](https://catalog.workshops.aws/genai-on-eks/en-US/50-getting-started/01-self-paced)

---

## Cleanup

To destroy all resources and avoid ongoing AWS charges:

```bash
terraform destroy --auto-approve
```

Or if you deployed to a custom region:

```bash
terraform destroy --auto-approve -var="region=us-west-2"
```

> The S3 bucket has `force_destroy = true` so it will be deleted even if it contains model files.

---

## Troubleshooting

| Issue                   | Solution                                                               |
| ----------------------- | ---------------------------------------------------------------------- |
| Timeout during apply    | Re-run `terraform apply` — some resources take time to stabilize       |
| kubectl auth errors     | Run `aws eks update-kubeconfig` again with the correct region          |
| GPU nodes not launching | Verify your account has quota for the GPU instance type in your region |
| Grafana shows no data   | Wait 2-3 minutes for Prometheus to start scraping and remote writing   |
