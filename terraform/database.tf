# ---------- Змінні для бази ----------
variable "db_name" {
  description = "Назва бази даних"
  type        = string
  default     = "labor_sql"
}

variable "db_username" {
  description = "Логін адміністратора бази"
  type        = string
  default     = "laptops_user"
}

variable "db_password" {
  description = "Пароль до бази. Задається у terraform.tfvars, який не потрапляє в git"
  type        = string
  sensitive   = true # Terraform не показує значення у виводі
}

variable "db_instance_class" {
  description = "Розмір сервера бази"
  type        = string
  default     = "db.t4g.micro"
}

# ---------- Група підмереж для бази ----------
# RDS вимагає підмережі щонайменше у двох зонах. Беремо ПРИВАТНІ.
resource "aws_db_subnet_group" "main" {
  name       = "${var.project}-db-subnets"
  subnet_ids = aws_subnet.private[*].id
}

# ---------- Керована база даних MySQL (RDS) ----------
resource "aws_db_instance" "main" {
  identifier     = "${var.project}-db"
  engine         = "mysql"
  engine_version = "8.4" # та сама версія, що й у нашому compose.yaml
  instance_class = var.db_instance_class

  allocated_storage = 20 # ГБ

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  # Мережа: приватні підмережі, без публічної адреси, лише для застосунку
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false

  storage_encrypted       = true
  multi_az                = false # одна зона, щоб заощадити кредит
  backup_retention_period = 1     # 1 день резервних копій (дає point-in-time recovery)

  # Щоб `terraform destroy` видаляв базу без залишку
  skip_final_snapshot = true
  deletion_protection = false
  apply_immediately   = true
}

# ---------- Результат: адреса бази (її отримає застосунок) ----------
output "db_endpoint" {
  value = aws_db_instance.main.address
}
