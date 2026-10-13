################################################################################
# ElastiCache Serverless (Valkey) for LMCache remote KV cache sharing
################################################################################

moved {
  from = aws_security_group.valkey
  to   = aws_security_group.valkey[0]
}

moved {
  from = aws_elasticache_serverless_cache.valkey
  to   = aws_elasticache_serverless_cache.valkey[0]
}

resource "aws_security_group" "valkey" {
  count = var.enable_valkey ? 1 : 0

  name        = "genai-workshop-valkey"
  description = "Allow LMCache pods to access ElastiCache Serverless Valkey"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Valkey TLS from the EKS cluster"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [module.eks.cluster_primary_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "genai-workshop-valkey"
  })
}

resource "aws_elasticache_serverless_cache" "valkey" {
  count = var.enable_valkey ? 1 : 0

  name                 = "lmcache-valkey-eks"
  description          = "LMCache shared L2 KV cache"
  engine               = "valkey"
  major_engine_version = "8"
  security_group_ids   = [aws_security_group.valkey[0].id]
  subnet_ids           = slice(module.vpc.private_subnets, 0, min(3, length(module.vpc.private_subnets)))

  cache_usage_limits {
    data_storage {
      maximum = 5
      unit    = "GB"
    }

    ecpu_per_second {
      maximum = 5000
    }
  }

  tags = local.tags
}
