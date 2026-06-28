# ============================================================
# Lesson 02 - 변수(variable) / 출력(output) / locals
# 목표: 하드코딩 제거, 값 주입 방식 익히기
#
# 🔒=예약어(고정)   ✏️=내 자유(변수·별명 이름, 값)
# ============================================================

terraform {                          # 🔒 terraform
  required_providers {               # 🔒 required_providers
    docker = {                       # ✏️ docker (provider 로컬 별명)
      source  = "kreuzwerker/docker" # 🔒 source  = ✏️ 값
      version = "~> 3.0"             # 🔒 version = ✏️ 값
    }
  }
}
provider "docker" {}                 # 🔒 provider / ✏️ "docker"

# 1) variable: 외부에서 주입받는 입력값 (함수의 매개변수 같은 것)
#   - 밖에서 바꿀 수 있는 값(환경마다 다른 것). 참조는 var.<이름> (단수 var)
#   - 값 주입 우선순위: CLI -var  >  *.tfvars  >  환경변수 TF_VAR_*  >  default
variable "container_name" {          # 🔒 variable / ✏️ "container_name"(변수이름)
  type        = string               # 🔒 type        = 🔒 string
  description = "컨테이너 이름"        # 🔒 description = ✏️ 값
  default     = "tf-var-web"          # 🔒 default     = ✏️ 값
}

variable "external_port" {           # 🔒 variable / ✏️ "external_port"
  type    = number                   # 🔒 type    = 🔒 number
  default = 8081                      # 🔒 default = ✏️ 8081
}

variable "image_tag" {               # 🔒 variable / ✏️ "image_tag"
  type    = string                   # 🔒 / 🔒
  default = "nginx:alpine"            # 🔒 / ✏️
}

# 2) locals: 코드 내부에서 재사용할 계산된 값 (외부 주입 불가)
#   - variable=밖에서 주입 / locals=안에서만 정함. 참조는 local.<이름> (단수 local!)
locals {                             # 🔒 locals
  common_labels = {                  # ✏️ common_labels (로컬 이름 — 내가 지음)
    managed_by = "terraform"         # ✏️ managed_by = ✏️ "terraform"  (맵 키도 내 자유)
    lesson     = "02"                # ✏️ lesson     = ✏️ "02"
  }
}

resource "docker_image" "nginx" {    # 🔒 resource / 🔒 "docker_image" / ✏️ "nginx"
  name         = var.image_tag       # 🔒 name = 🔒 var + ✏️ image_tag(변수이름)
  keep_locally = false               # 🔒 / ✏️
}

resource "docker_container" "web" {  # 🔒 resource / 🔒 "docker_container" / ✏️ "web"
  image = docker_image.nginx.image_id # 🔒 image = 🔒 docker_image + ✏️ nginx + 🔒 image_id
  name  = var.container_name         # 🔒 name = 🔒 var + ✏️ container_name

  ports {                            # 🔒 ports
    internal = 80                    # 🔒 / ✏️
    external = var.external_port      # 🔒 external = 🔒 var + ✏️ external_port
  }

  ## 라벨을 여러개 붙이는 것. (컨테이너는 1개! 그 "안"의 labels 블록만 반복)
  #   dynamic 부품 4개: ①dynamic"labels"=무슨 블록 ②for_each=몇 번(맵 항목 2 → 2바퀴)
  #                     ③content=한 바퀴에 만들 내용 ④lb.key/value=현재 항목(iterator=lb로 이름 지정)
  #   ※ for_each가 resource 바로 밑이면 "리소스 자체" 반복(03), dynamic 안이면 "블록만" 반복
  dynamic "labels" {                 # 🔒 dynamic / ✏️ "labels"(만들 블록 이름)
    for_each = local.common_labels   # 🔒 for_each = 🔒 local + ✏️ common_labels
    iterator = lb                    # 🔒 iterator = ✏️ lb (반복변수 이름 — 내가 지음)
    content {                        # 🔒 content
      label = lb.key                 # 🔒 label = ✏️ lb(반복변수) + 🔒 key
      value = lb.value               # 🔒 value = ✏️ lb + 🔒 value
    }
  }
}

output "container_name" {            # 🔒 output / ✏️ "container_name"(출력이름)
  value = docker_container.web.name  # 🔒 value = 🔒 docker_container + ✏️ web + 🔒 name
}
output "url" {                       # 🔒 output / ✏️ "url"
  value = "http://localhost:${var.external_port}" # 🔒 value = ✏️ 값(var.external_port 참조)
}
