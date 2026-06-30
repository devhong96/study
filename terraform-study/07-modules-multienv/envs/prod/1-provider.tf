# [흐름 1/4] prod 환경의 루트 모듈 — provider 설정 (dev와 100% 동일 구조)
terraform {                     # 🔒 terraform
  required_version = ">= 1.5"
  required_providers {
    aws = {                     # ✏️ aws
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {                # 🔒 provider / ✏️ "aws"
  region = var.region           # 🔒 region = 🔒 var + ✏️ region
}
