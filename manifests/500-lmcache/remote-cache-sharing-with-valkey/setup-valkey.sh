#!/bin/bash
# Provision Amazon ElastiCache Serverless (Valkey) inside the EKS VPC for LMCache L2.
# Exports VALKEY_ENDPOINT (and VALKEY_SG) so the pod manifest can be envsubst'd.
#
# Requires: AWS_REGION env var. Cluster name defaults to "genai-workshop" (override via CLUSTER_NAME).
# Usage: source ./setup-valkey.sh
#
# NOTE: No `set -e` — this script is meant to be `source`d. A hard exit would
# kill the caller's shell. We handle errors explicitly and make each step
# idempotent so re-running the script recovers cleanly.

if [ -z "$AWS_REGION" ]; then
  echo "ERROR: AWS_REGION must be set"
  return 1 2>/dev/null || exit 1
fi

CLUSTER_NAME="${CLUSTER_NAME:-genai-workshop}"
CACHE_NAME="${CACHE_NAME:-lmcache-valkey-eks}"
SG_NAME="${SG_NAME:-genai-workshop-valkey}"

# Discover EKS VPC and cluster security group
VPC=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" \
  --query 'cluster.resourcesVpcConfig.vpcId' --output text 2>/dev/null)
EKS_SG=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" \
  --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text 2>/dev/null)
if [ -z "$VPC" ] || [ "$VPC" = "None" ]; then
  echo "ERROR: could not find EKS cluster '$CLUSTER_NAME' in region $AWS_REGION"
  return 1 2>/dev/null || exit 1
fi

# Reuse existing security group if present, else create it
export VALKEY_SG=$(aws ec2 describe-security-groups --region "$AWS_REGION" \
  --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC" \
  --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)
if [ -z "$VALKEY_SG" ] || [ "$VALKEY_SG" = "None" ]; then
  export VALKEY_SG=$(aws ec2 create-security-group --region "$AWS_REGION" \
    --group-name "$SG_NAME" \
    --description "LMCache Valkey access" \
    --vpc-id "$VPC" --query 'GroupId' --output text)
  echo "Created security group: $VALKEY_SG"
  aws ec2 authorize-security-group-ingress --region "$AWS_REGION" \
    --group-id "$VALKEY_SG" --protocol tcp --port 6379 --source-group "$EKS_SG" >/dev/null 2>&1
else
  echo "Reusing existing security group: $VALKEY_SG"
fi

# Reuse existing Valkey cluster if present, else create it
EXISTING_STATUS=$(aws elasticache describe-serverless-caches --region "$AWS_REGION" \
  --serverless-cache-name "$CACHE_NAME" \
  --query 'ServerlessCaches[0].Status' --output text 2>/dev/null)
if [ -n "$EXISTING_STATUS" ] && [ "$EXISTING_STATUS" != "None" ]; then
  echo "Reusing existing Valkey cluster: $CACHE_NAME (status=$EXISTING_STATUS)"
else
  # Pick two private subnets in different AZs in the EKS VPC
  SUBNET_A=$(aws ec2 describe-subnets --region "$AWS_REGION" \
    --filters Name=vpc-id,Values="$VPC" "Name=tag:Name,Values=*private-${AWS_REGION}a" \
    --query 'Subnets[0].SubnetId' --output text)
  SUBNET_B=$(aws ec2 describe-subnets --region "$AWS_REGION" \
    --filters Name=vpc-id,Values="$VPC" "Name=tag:Name,Values=*private-${AWS_REGION}b" \
    --query 'Subnets[0].SubnetId' --output text)

  aws elasticache create-serverless-cache --region "$AWS_REGION" \
    --serverless-cache-name "$CACHE_NAME" \
    --engine valkey --major-engine-version 8 \
    --security-group-ids "$VALKEY_SG" \
    --subnet-ids "$SUBNET_A" "$SUBNET_B" \
    --cache-usage-limits 'DataStorage={Maximum=5,Unit=GB},ECPUPerSecond={Maximum=5000}' >/dev/null
  echo "Creating Valkey cluster: $CACHE_NAME"
fi

# Wait until available
echo "Waiting for Valkey cluster $CACHE_NAME to become available..."
for i in $(seq 1 40); do
  STATUS=$(aws elasticache describe-serverless-caches --region "$AWS_REGION" \
    --serverless-cache-name "$CACHE_NAME" \
    --query 'ServerlessCaches[0].Status' --output text 2>/dev/null)
  [ "$STATUS" = "available" ] && break
  echo "  status=$STATUS"
  sleep 15
done
if [ "$STATUS" != "available" ]; then
  echo "ERROR: Valkey cluster did not become available in time (last status=$STATUS)"
  return 1 2>/dev/null || exit 1
fi

export VALKEY_ENDPOINT=$(aws elasticache describe-serverless-caches --region "$AWS_REGION" \
  --serverless-cache-name "$CACHE_NAME" \
  --query 'ServerlessCaches[0].Endpoint.Address' --output text)

echo "Valkey security group: $VALKEY_SG"
echo "Valkey endpoint: $VALKEY_ENDPOINT"
