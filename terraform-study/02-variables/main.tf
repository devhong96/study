# ============================================================
# Lesson 02 - 변수(variable) / 출력(output) / locals
# 목표: 하드코딩 제거, 값 주입 방식 익히기
# ============================================================

terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}
provider "docker" {}

# 1) variable: 외부에서 주입받는 입력값 (함수의 매개변수 같은 것)
variable "container_name" {
  type        = string
  description = "컨테이너 이름"
  default     = "tf-var-web" # default 있으면 안 넣어도 됨
}

variable "external_port" {
  type    = number
  default = 8081
}

variable "image_tag" {
  type    = string
  default = "nginx:alpine"
}

# 2) locals: 코드 내부에서 재사용할 계산된 값 (외부 주입 불가, 상수/조합용)
locals {
  common_labels = {
    managed_by = "terraform"
    lesson     = "02"
  }
}

resource "docker_image" "nginx" {
  name         = var.image_tag # ← var.<이름> 으로 참조
  keep_locally = false
}

resource "docker_container" "web" {
  image = docker_image.nginx.image_id
  name  = var.container_name

  ports {
    internal = 80
    external = var.external_port
  }

  # locals 사용 + dynamic 하게 라벨 반복 생성
  dynamic "labels" {
    for_each = local.common_labels
    content {
      label = labels.key
      value = labels.value
    }
  }
}

output "container_name" {
  value = docker_container.web.name
}
output "url" {
  value = "http://localhost:${var.external_port}"
}
