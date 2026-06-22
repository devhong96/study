# ============================================================
# Lesson 06 - ECS 컨테이너 CI/CD 파이프라인
# 그림: git push → CodePipeline → CodeBuild → ECR → ECS → ALB
# 이 파일: "어떤 클라우드에, 어떻게 접속할지" 설정
# ============================================================

# terraform 블록 = 테라폼 자체 설정 (리소스를 만들지 않음. init이 이걸 읽음)
terraform {
  required_version = ">= 1.5" # 이 코드는 테라폼 1.5 이상에서만 실행 (옛 버전 사고 방지)

  # 어떤 provider(=클라우드를 다루는 플러그인)를 쓸지 선언
  required_providers {
    aws = {
      source  = "hashicorp/aws" # AWS 공식 provider (Terraform Registry 주소)
      version = "~> 5.0"         # 5.x 버전대만 사용 (~> 는 "메이저는 고정, 마이너는 허용")
    }
  }
}

# provider 블록 = 위에서 선언한 AWS에 "실제로 어떻게 붙을지"
# 인증키(access key)는 절대 여기 안 적는다! ~/.aws/credentials·환경변수·IAM Role에서 자동으로 읽어감.
provider "aws" {
  region = var.region # 어느 지역(리전)에 만들지. 예: ap-northeast-2(서울)
}

# data 블록 = 만드는 게 아니라 "조회"만 함.
# 지금 이 AWS 계정의 ID(숫자)를 가져온다. → 아래에서 S3 버킷 이름을 전 세계 고유하게 만들 때 사용.
data "aws_caller_identity" "current" {}
