terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.23.0" # з цієї версії провайдер розуміє вхід через `aws login`
    }
  }
}

provider "aws" {
  region = var.region

  # Ці теги автоматично додаються до ВСІХ ресурсів.
  # Так у консолі легко побачити, що створено Terraform'ом і для чого.
  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
    }
  }
}

# Запит на читання: "хто я?" (нічого не створює)
data "aws_caller_identity" "me" {}
