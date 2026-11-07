variable "region" {
  description = "Регіон AWS, у якому створюються всі ресурси"
  type        = string
  default     = "eu-north-1" # Стокгольм
}

variable "project" {
  description = "Префікс для імен ресурсів"
  type        = string
  default     = "laptops"
}
