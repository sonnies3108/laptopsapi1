# ======================================================================
# Lab 2, завдання 3 і 4: панель моніторингу та сповіщення на email
# ======================================================================

variable "alert_email" {
  description = "Email, на який надходять сповіщення. Задається в terraform.tfvars"
  type        = string
}

locals {
  cluster_name = aws_ecs_cluster.main.name
  service_name = aws_ecs_service.app.name
  lb_suffix    = aws_lb.main.arn_suffix
}

# ---------- Дашборд: п'ять графіків ----------
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project}-autoscaling"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title  = "1. Екземпляри: бажана і фактична кількість"
          region = var.region
          view   = "timeSeries"
          stat   = "Average"
          period = 60
          metrics = [
            ["ECS/ContainerInsights", "DesiredTaskCount", "ClusterName", local.cluster_name, "ServiceName", local.service_name, { label = "Desired (бажана)" }],
            ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", local.cluster_name, "ServiceName", local.service_name, { label = "Running (фактична)" }],
          ]
          yAxis = { left = { min = 0 } }
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title  = "2. Завантаження CPU сервісу, %"
          region = var.region
          view   = "timeSeries"
          stat   = "Average"
          period = 60
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", local.cluster_name, "ServiceName", local.service_name, { label = "CPU, середнє" }],
          ]
          annotations = {
            horizontal = [
              { label = "ціль скейлінгу", value = var.cpu_target },
              { label = "поріг алерта", value = 70 },
            ]
          }
          yAxis = { left = { min = 0, max = 100 } }
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title  = "3. Запити за хвилину"
          region = var.region
          view   = "timeSeries"
          stat   = "Sum"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", local.lb_suffix, { label = "Запитів/хв" }],
          ]
          yAxis = { left = { min = 0 } }
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6
        properties = {
          title  = "4. Латентність p95, с"
          region = var.region
          view   = "timeSeries"
          stat   = "p95"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", local.lb_suffix, { label = "p95" }],
          ]
          annotations = {
            horizontal = [{ label = "0.5 с", value = 0.5 }]
          }
          yAxis = { left = { min = 0 } }
        }
      },
      {
        type = "metric", x = 0, y = 12, width = 12, height = 6
        properties = {
          title  = "5. Відповіді 5xx за хвилину"
          region = var.region
          view   = "timeSeries"
          stat   = "Sum"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", local.lb_suffix, { label = "5xx" }],
          ]
          yAxis = { left = { min = 0 } }
        }
      },
    ]
  })
}

# ---------- Додатковий дашборд для завдання 5 (кеш і база) ----------
resource "aws_cloudwatch_dashboard" "cache" {
  dashboard_name = "${var.project}-cache"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title  = "Навантаження на базу: CPU RDS, %"
          region = var.region
          view   = "timeSeries"
          stat   = "Average"
          period = 60
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", aws_db_instance.main.identifier],
          ]
          yAxis = { left = { min = 0, max = 100 } }
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title  = "Підключення до бази"
          region = var.region
          view   = "timeSeries"
          stat   = "Maximum"
          period = 60
          metrics = [
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", aws_db_instance.main.identifier],
          ]
          yAxis = { left = { min = 0 } }
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title  = "Кеш: влучання і промахи за хвилину"
          region = var.region
          view   = "timeSeries"
          stat   = "Sum"
          period = 60
          metrics = [
            ["AWS/ElastiCache", "CacheHits", "CacheClusterId", aws_elasticache_cluster.cache.cluster_id],
            ["AWS/ElastiCache", "CacheMisses", "CacheClusterId", aws_elasticache_cluster.cache.cluster_id],
          ]
          yAxis = { left = { min = 0 } }
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6
        properties = {
          title  = "Латентність p95, с"
          region = var.region
          view   = "timeSeries"
          stat   = "p95"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", local.lb_suffix],
          ]
          yAxis = { left = { min = 0 } }
        }
      },
    ]
  })
}

# ---------- Сповіщення: SNS-тема + підписка email ----------
resource "aws_sns_topic" "alerts" {
  name = "${var.project}-alerts"
}

# Після apply на пошту прийде лист "AWS Notification - Subscription Confirmation".
# Без натискання "Confirm subscription" листи сповіщень не доставлятимуться.
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Умова: середній CPU > 70% протягом 2 хвилин поспіль.
# alarm_actions: лист при переході в ALARM, ok_actions: другий лист при поверненні до норми.
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.project}-cpu-high"
  alarm_description   = "CPU сервісу > 70% протягом 2 хвилин"
  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 70
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.app.name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

output "dashboard_url" {
  value = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}
