# We use the kubectl provider here because:
# 1. Its one less provider and the kubectl provider is already in use elsewhere
# 2. The Kubernetes provider is problematic, wanting to reach out to the API server
#    quite earlier in the process and usually fails, plus it does not support retries
#    which the kubectl provider does (making it more resilient to transient issues)
# 3. Its easier to copy+paste the YAML body and deploy directly, outside of Terraform

################################################################################
# Download model from HuggingFace and upload to S3 bucket
# This:
# 1. Downloads all model files directly from HuggingFace Hub
# 2. Pre-pulls model during account provisioning which avoids this
#    time penalty during the workshop event
# 3. Uses S3 for scalable, cost-effective model storage
# 4. Leverages EKS Pod Identity for secure S3 access
################################################################################
resource "kubectl_manifest" "job_model_download" {
  depends_on = [
    module.eks,
    module.eks.cluster_addons,
    kubectl_manifest.model_storage_service_account,
    aws_eks_pod_identity_association.model_storage,
    aws_s3_bucket.model_storage
  ]

  force_new = true
  yaml_body = <<-YAML
    apiVersion: batch/v1
    kind: Job
    metadata:
      name: model-download
      namespace: default
    spec:
      ttlSecondsAfterFinished: 604800  # Keep completed pods for 7 days
      backoffLimit: 10
      activeDeadlineSeconds: 3600  # 1 hour timeout
      completionMode: NonIndexed
      completions: 1
      template:
        spec:
          serviceAccountName: ${kubectl_manifest.model_storage_service_account.name}
          restartPolicy: Never
          containers:
            - name: validate-pod-identity
              image: public.ecr.aws/aws-cli/aws-cli:latest
              command: ['/bin/sh', '-c']
              args:
                - |
                  set -e
                  
                  echo 'Checking Pod Identity...'
                  EXPECTED_ROLE="genai-model-storage-role"
                  CURRENT_ROLE=$(aws sts get-caller-identity --query 'Arn' --output text | cut -d'/' -f2 2>/dev/null || echo "unknown")
                  
                  echo "Expected role: $EXPECTED_ROLE"
                  echo "Current role: $CURRENT_ROLE"
                  
                  if [ "$CURRENT_ROLE" != "$EXPECTED_ROLE" ]; then
                    echo "ERROR: Pod Identity not working. Using node role instead of Pod Identity role."
                    echo "Pod will be recreated to retry Pod Identity association."
                    exit 1
                  fi
                  
                  echo "Pod Identity verified successfully!"
            - name: download
              image: python:3.11-slim
              env:
                - name: HF_HUB_DISABLE_XET
                  value: "1"
              command: ["/bin/bash", "-c"]
              args:
                - |
                  set -e
                  pip install -q huggingface_hub boto3

                  export MODEL_PREFIX="${trimsuffix(var.model_prefix, "/")}"
                  export LOCAL_DIR="/tmp/$MODEL_PREFIX"
                  
                  echo "Downloading Ministral-3-8B-Instruct-2512 from HuggingFace..."
                  python3 -c "from huggingface_hub import snapshot_download; snapshot_download('mistralai/Ministral-3-8B-Instruct-2512', local_dir='$LOCAL_DIR', allow_patterns=['*.json', '*.txt', '*.md', '*.model', 'consolidated.safetensors'])"
                  
                  echo "Uploading to S3 bucket: ${aws_s3_bucket.model_storage.bucket}"
                  python3 << EOF
                  import boto3
                  import os
                  from pathlib import Path

                  s3 = boto3.client('s3')
                  bucket = "${aws_s3_bucket.model_storage.bucket}"
                  model_prefix = os.environ['MODEL_PREFIX']
                  local_dir = Path(os.environ['LOCAL_DIR'])

                  for file_path in local_dir.rglob("*"):
                      if file_path.is_file():
                          # Skip .cache directories and their contents
                          if '.cache' in file_path.parts:
                              continue
                          s3_key = f"{model_prefix}/{file_path.relative_to(local_dir)}"
                          print(f"Uploading {file_path.name}...")
                          s3.upload_file(str(file_path), bucket, s3_key)

                  print("Upload complete!")
                  EOF
              resources:
                requests:
                  memory: "4Gi"
                  cpu: "2"
                limits:
                  memory: "8Gi"
                  cpu: "4"
  YAML
}
