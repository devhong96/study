# [흐름 1/4] dev 환경의 루트 모듈 — provider 설정 (terraform apply를 여기서 실행)
#   🔒=예약어  ✏️=내 자유
terraform {                     # 🔒 terraform
  required_version = ">= 1.5"   # 🔒 = ✏️
  required_providers {          # 🔒
    aws = {                     # ✏️ aws (로컬 별명)
      source  = "hashicorp/aws" # 🔒 = ✏️
      version = "~> 5.0"        # 🔒 = ✏️
    }
  }
}

provider "aws" {                # 🔒 provider / ✏️ "aws"
  region = var.region           # 🔒 region(칸) = 🔒 var + ✏️ region(변수이름)
}
