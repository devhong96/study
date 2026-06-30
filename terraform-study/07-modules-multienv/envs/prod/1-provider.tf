# ── prod 환경의 루트 모듈 ── provider 설정 (dev와 동일 구조)
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}
