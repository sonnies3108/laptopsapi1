output "account_id" {
  value = data.aws_caller_identity.me.account_id
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}
