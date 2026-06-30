# 모듈도 자신이 어떤 provider를 요구하는지 명시(권장). provider 블록은 루트(env)에서 둠.
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
