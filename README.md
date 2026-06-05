# Generative AI on Amazon EKS

Deploy and run Large Language Model (LLM) inference workloads on Amazon EKS with GPU acceleration, observability, and model storage — all provisioned with Terraform.

**📺 Watch: How to deploy this workshop in your own AWS account**

[![▶ Watch on YouTube](https://ytcards.demolab.com/?id=NPHvJ599bV0&title=%E2%96%B6+Watch+on+YouTube&lang=en&timestamp=0&background_color=%23f89530&title_color=%23ffffff&stats_color=%23ffffff&max_title_lines=2&width=480&border_radius=5)](https://s12d.com/self-paced-workshop-youtube)

![Architecture](./architecture.png)

## What's Included

- **Terraform infrastructure** — EKS Auto Mode cluster, VPC, S3 model storage, Amazon Managed Prometheus, Grafana dashboards, and IAM roles
- **Kubernetes manifests** — Ready-to-deploy configurations for inference workloads

## Target Audience

This workshop is intended for Machine Learning Scientists/Engineers, Data Scientists/Engineers, Prompt Engineers, Developers, and Technical Founders.

While not mandatory, participants will benefit from:

- Basic knowledge of ML frameworks (PyTorch, Hugging Face Transformers)
- Fundamental understanding of Kubernetes concepts
- Familiarity with Python programming

New to Amazon EKS? We recommend completing the [EKS Workshop](https://www.eksworkshop.com/) first.

## Prerequisites

- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) (>= 2.x)
- [Terraform](https://developer.hashicorp.com/terraform/install) (>= 1.3)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- AWS account with GPU instance quota

## Getting Started

See [terraform/README.md](./terraform/README.md) for full deployment instructions.

## Repository Structure

```text
.
├── terraform/          # Infrastructure as Code (EKS, VPC, S3, AMP, Grafana)
│   ├── grafana-dashboards/   # Pre-built Grafana dashboard JSON files
│   ├── main.tf               # Provider and locals configuration
│   ├── eks.tf                # EKS cluster and S3 CSI driver
│   ├── vpc.tf                # VPC and networking
│   ├── helm.tf               # Observability stack (Prometheus, Grafana)
│   ├── amp.tf                # Amazon Managed Prometheus
│   ├── variables.tf          # Configurable variables
│   └── ...
└── manifests/          # Kubernetes manifests for inference workloads
```

## Cleanup

```bash
cd terraform
terraform destroy --auto-approve
```

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the LICENSE file.
