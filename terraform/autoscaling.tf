# ======================================================================
# Lab 2, завдання 1: автоматичне горизонтальне масштабування ECS-сервісу
# ======================================================================

variable "min_capacity" {
  description = "Мінімальна кількість екземплярів (tasks)"
  type        = number
  default     = 1
}

variable "max_capacity" {
  description = "Максимальна кількість екземплярів (за умовою лаби не більше 4)"
  type        = number
  default     = 3

  validation {
    condition     = var.max_capacity <= 4
    error_message = "За умовою лабораторної максимум екземплярів не більше 4."
  }
}

variable "cpu_target" {
  description = "Цільове середнє завантаження CPU, %"
  type        = number
  default     = 60
}

variable "scale_out_cooldown" {
  description = "Скільки секунд після додавання екземпляра не додавати наступний"
  type        = number
  default     = 60
}

variable "scale_in_cooldown" {
  description = "Скільки секунд після останньої зміни не вилучати екземпляри"
  type        = number
  default     = 300
}

# "Що масштабуємо": бажана кількість tasks сервісу ECS у межах [min, max]
resource "aws_appautoscaling_target" "app" {
  service_namespace  = "ecs"
  scalable_dimension = "ecs:service:DesiredCount"
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
  min_capacity       = var.min_capacity
  max_capacity       = var.max_capacity
}

# "Як масштабуємо": target tracking. AWS сам тримає середній CPU біля cpu_target:
# вище цілі додає екземпляри, нижче (з великою затримкою) вилучає.
resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.project}-cpu-target-tracking"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.app.service_namespace
  scalable_dimension = aws_appautoscaling_target.app.scalable_dimension
  resource_id        = aws_appautoscaling_target.app.resource_id

  target_tracking_scaling_policy_configuration {
    target_value       = var.cpu_target
    scale_out_cooldown = var.scale_out_cooldown
    scale_in_cooldown  = var.scale_in_cooldown

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}
