# ============================================================
# Lesson 05 - AWS EC2 (실무 파일 분리 관례)
# 이 파일: provider 설정 (어떤 클라우드에 어떻게 접속할지)
#
# 🔒=예약어(고정, 못 바꿈)   ✏️=내 자유(별명·값)
#   판별: 블록키워드 / 타입(첫 따옴표) / =왼쪽 칸이름 / string·true·var·data = 🔒
#         두번째 따옴표 별명 / =오른쪽 값 / 변수·출력 이름 / tags 키        = ✏️
# ============================================================

terraform {                     # 🔒 terraform
  required_version = ">= 1.5"   # 🔒 required_version = ✏️ ">= 1.5"

  required_providers {          # 🔒 required_providers
    aws = {                     # ✏️ aws (provider 로컬 별명 — 내가 지음)
      source  = "hashicorp/aws" # 🔒 source  = ✏️ "hashicorp/aws"
      version = "~> 5.0"        # 🔒 version = ✏️ "~> 5.0"
    }
  }
}

# 인증정보(access key)는 코드에 안 적는다! ~/.aws/credentials·환경변수·`aws configure`에서 자동.
provider "aws" {                # 🔒 provider / ✏️ "aws"(어느 provider 쓸지)
  region = var.region           # 🔒 region(AWS가 정한 칸) = 🔒 var + ✏️ region(내 변수이름)
  #        ↑ "region ="의 region은 고정 / "var.region"의 region은 내가 지은 변수이름 — 같은 단어, 다른 역할!
}
