# ============================================================
# Lesson 05 - AWS EC2 (실무 파일 분리 관례)
# 이 파일: provider 설정 (어떤 클라우드에 어떻게 접속할지)
# ============================================================

terraform {
  required_version = ">= 1.5" # 테라폼 버전 하한

  required_providers {
    aws = {
      source  = "hashicorp/aws" # 공식 AWS provider
      version = "~> 5.0"        # 5.x 사용
    }
  }
}

# AWS provider 설정
# 인증정보(access key 등)는 코드에 안 적는다! (절대 하드코딩 금지)
# 대신 ~/.aws/credentials, 환경변수(AWS_ACCESS_KEY_ID...),
# 또는 `aws configure`로 설정한 걸 테라폼이 자동으로 읽어감.
provider "aws" {
  region = var.region # 예: ap-northeast-2 (서울)
}
