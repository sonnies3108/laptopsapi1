# ======================================================================
# Lab 2, завдання 5: спільний кеш Redis (Amazon ElastiCache)
# Один Redis на всі екземпляри застосунку, тому кеш однаковий для всіх.
# ======================================================================

variable "cache_enabled" {
  description = "Чи використовує застосунок кеш (глобальний вимикач)"
  type        = bool
  default     = true
}

variable "cache_ttl_seconds" {
  description = "Термін дії запису в кеші, секунди (за умовою 30-60)"
  type        = number
  default     = 45
}

variable "cache_node_type" {
  description = "Розмір вузла Redis"
  type        = string
  default     = "cache.t4g.micro"
}

resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.project}-cache-subnets"
  subnet_ids = aws_subnet.private[*].id # кеш у приватних підмережах, як і база
}

resource "aws_security_group" "cache" {
  name        = "${var.project}-cache-sg"
  description = "Security group for Redis"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Redis only from the application"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }
}

resource "aws_elasticache_cluster" "cache" {
  cluster_id           = "${var.project}-cache"
  engine               = "redis"
  engine_version       = "7.1"
  node_type            = var.cache_node_type
  num_cache_nodes      = 1
  port                 = 6379
  parameter_group_name = "default.redis7"
  subnet_group_name    = aws_elasticache_subnet_group.main.name
  security_group_ids   = [aws_security_group.cache.id]
  apply_immediately    = true
}
