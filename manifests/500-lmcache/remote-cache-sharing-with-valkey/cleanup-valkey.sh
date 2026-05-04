#!/bin/bash
# Delete the ElastiCache Serverless (Valkey) cluster and its dedicated security group.
#
# Requires: AWS_REGION env var.
# Usage: ./cleanup-valkey.sh

set -e

: "${AWS_REGION:?AWS_REGION must be set}"
CACHE_NAME="${CACHE_NAME:-lmcache-valkey-eks}"
SG_NAME="${SG_NAME:-genai-workshop-valkey}"

# Delete the Serverless Valkey cluster (returns immediately, deletion runs async)
echo "Deleting Valkey cluster $CACHE_NAME..."
aws elasticache delete-serverless-cache --region "$AWS_REGION" \
  --serverless-cache-name "$CACHE_NAME" >/dev/null 2>&1 || echo "  (cache already deleted or not found)"

# Wait until the cluster is fully gone (SG can only be deleted once ENIs are released)
echo "Waiting for Valkey deletion to finish..."
while aws elasticache describe-serverless-caches --region "$AWS_REGION" \
    --serverless-cache-name "$CACHE_NAME" >/dev/null 2>&1; do
  STATUS=$(aws elasticache describe-serverless-caches --region "$AWS_REGION" \
    --serverless-cache-name "$CACHE_NAME" \
    --query 'ServerlessCaches[0].Status' --output text 2>/dev/null || echo "gone")
  [ "$STATUS" = "gone" ] && break
  echo "  status=$STATUS"; sleep 15
done

# Delete the security group
VALKEY_SG=$(aws ec2 describe-security-groups --region "$AWS_REGION" \
  --filters "Name=group-name,Values=$SG_NAME" \
  --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)
if [ -n "$VALKEY_SG" ] && [ "$VALKEY_SG" != "None" ]; then
  echo "Deleting security group $VALKEY_SG..."
  aws ec2 delete-security-group --region "$AWS_REGION" --group-id "$VALKEY_SG"
else
  echo "Security group $SG_NAME not found, skipping."
fi

unset VALKEY_ENDPOINT VALKEY_SG
echo "Cleanup complete."
