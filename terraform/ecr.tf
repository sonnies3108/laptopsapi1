# ---------- ECR: приватний реєстр Docker-образів ----------
resource "aws_ecr_repository" "app" {
  name                 = "${var.project}-api"
  image_tag_mutability = "MUTABLE"
  force_delete         = true # щоб `terraform destroy` видаляв реєстр навіть з образами

  image_scanning_configuration {
    scan_on_push = true # AWS перевіряє образ на відомі вразливості
  }
}
