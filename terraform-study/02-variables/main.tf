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
#   - 밖에서 바꿀 수 있는 값(환경마다 다른 것: 포트·리전·IP). dev/prod 분리의 출발점
#   - 참조는 var.<이름> (단수 var)
#   - 값 주입 우선순위: CLI -var  >  *.tfvars  >  환경변수 TF_VAR_*  >  default
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
#   - variable과 차이: variable=밖에서 주입 / locals=안에서만 정함(private final 필드 같은 것)
#   - 참조는 local.<이름> (단수 local — 정의는 locals 복수, 참조는 local 단수!)
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
  # dynamic "labels" {
  #   for_each = local.common_labels
  #   content {
  #     label = labels.key
  #     value = labels.value
  #   }
  # }


  ## 라벨을 여러개 붙이는 것. (컨테이너는 1개! 그 "안"의 labels 블록만 반복)
  #   dynamic 부품 4개:
  #     ① dynamic "labels" : 무슨 블록을 만들지 (블록 이름)
  #     ② for_each         : 몇 번/무엇을 돌지. 맵 항목 수 = 도는 횟수 (여기선 2개 → 2바퀴)
  #     ③ content          : 한 바퀴마다 만들 블록 한 개의 내용
  #     ④ lb.key / lb.value: 현재 회차 항목의 키/값 (iterator=lb로 반복변수 이름을 lb로 지정;
  #                          안 적으면 블록 이름 그대로 labels.key/labels.value)
  #   ※ for_each가 resource 바로 밑이면 "리소스 자체"를 반복(03), dynamic 안이면 "블록만" 반복
  dynamic "labels" {
    for_each = local.common_labels
    iterator = lb
    content {
      label = lb.key
      value = lb.value
    }
  }
}

output "container_name" {
  value = docker_container.web.name
}
output "url" {
  value = "http://localhost:${var.external_port}"
}
