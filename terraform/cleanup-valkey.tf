################################################################################
# Cleanup ElastiCache Serverless (Valkey) resources on destroy
#
# The KV Cache workshop module provisions Valkey via a shell script (outside
# Terraform state). This null_resource ensures those resources are cleaned up
# during `terraform destroy` so they don't block VPC deletion or incur charges.
#
# Handles all states: nothing exists, only SG, only cache, both, or already
# cleaned up. Valkey must be fully deleted before the SG can be removed
# because the SG is attached to the cache's network configuration.
################################################################################

resource "null_resource" "cleanup_valkey" {
  triggers = {
    region     = local.region
    cache_name = "lmcache-valkey-eks"
    sg_name    = "genai-workshop-valkey"
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      REGION="${self.triggers.region}"
      CACHE_NAME="${self.triggers.cache_name}"
      SG_NAME="${self.triggers.sg_name}"

      # Step 1: Delete Valkey cluster if it exists
      STATUS=$(aws elasticache describe-serverless-caches \
        --serverless-cache-name "$CACHE_NAME" \
        --region "$REGION" \
        --query 'ServerlessCaches[0].Status' \
        --output text 2>/dev/null)

      if [ -n "$STATUS" ] && [ "$STATUS" != "None" ]; then
        echo "Found Valkey cluster $CACHE_NAME (status=$STATUS), deleting..."

        if [ "$STATUS" != "deleting" ]; then
          aws elasticache delete-serverless-cache \
            --serverless-cache-name "$CACHE_NAME" \
            --region "$REGION" 2>/dev/null
        fi

        echo "Waiting for Valkey cluster to be fully deleted..."
        for i in $(seq 1 40); do
          STATUS=$(aws elasticache describe-serverless-caches \
            --serverless-cache-name "$CACHE_NAME" \
            --region "$REGION" \
            --query 'ServerlessCaches[0].Status' \
            --output text 2>/dev/null)
          if [ -z "$STATUS" ] || [ "$STATUS" = "None" ]; then
            echo "Valkey cluster deleted."
            break
          fi
          echo "  status=$STATUS, waiting..."
          sleep 15
        done

        # Final check: if still not deleted after 10 minutes, warn but continue
        if [ -n "$STATUS" ] && [ "$STATUS" != "None" ]; then
          echo "WARNING: Valkey cluster still deleting after timeout. SG cleanup may fail."
        fi
      else
        echo "No Valkey cluster found, skipping."
      fi

      # Step 2: Delete security group if it exists
      SG_ID=$(aws ec2 describe-security-groups \
        --region "$REGION" \
        --filters "Name=group-name,Values=$SG_NAME" \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null)

      if [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
        echo "Found security group $SG_ID ($SG_NAME), deleting..."
        aws ec2 delete-security-group \
          --group-id "$SG_ID" \
          --region "$REGION"
        echo "Security group deleted."
      else
        echo "No Valkey security group found, skipping."
      fi
    EOT
  }
}
