# [흐름 1/4] modules/webserver — 이 모듈이 요구하는 provider 선언
#   provider "블록"은 여기 두지 않는다(루트=env에서 둠). 모듈은 "요구사항"만 명시.
#   🔒=예약어(고정)  ✏️=내 자유
terraform {                     # 🔒 terraform
  required_version = ">= 1.5"   # 🔒 required_version = ✏️ ">= 1.5"
  required_providers {          # 🔒 required_providers
    aws = {                     # ✏️ aws (provider 로컬 별명)
      source  = "hashicorp/aws" # 🔒 source  = ✏️ 값
      version = "~> 5.0"        # 🔒 version = ✏️ 값
    }
  }
}
