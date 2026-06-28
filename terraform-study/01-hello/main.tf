# ============================================================
# Lesson 01 - Hello Terraform (Docker provider)
# 목표: provider / resource / 핵심 사이클(init→plan→apply→destroy) 체득
#
# 🔒=예약어(고정: 블록키워드·타입(첫 따옴표)·=왼쪽 칸이름·false/true)
# ✏️=내 자유(두번째 따옴표 별명·=오른쪽 값)
# ============================================================

# 1) terraform 블록: 이 코드가 어떤 provider(플러그인)를 쓸지 선언
terraform {                          # 🔒 terraform
  required_version = ">= 1.5"        # 🔒 required_version = ✏️ ">= 1.5"

  required_providers {               # 🔒 required_providers
    docker = {                       # ✏️ docker (provider 로컬 별명 — 내가 지음)
      source  = "kreuzwerker/docker" # 🔒 source  = ✏️ "kreuzwerker/docker"
      version = "~> 3.0"             # 🔒 version = ✏️ "~> 3.0"
    }
  }
}

# 2) provider 블록: 실제 대상(여기선 로컬 Docker)에 어떻게 접속할지 설정
provider "docker" {}                 # 🔒 provider / ✏️ "docker"(위 로컬 별명과 매칭) / {} 빈 설정

# 3) resource 블록: "이런 리소스가 존재하게 해줘" 라고 선언
#    형식: resource "<리소스타입>" "<이름(코드 내 식별자)>" { ... }

# 3-1) nginx 이미지를 받아온다
#   ① docker_image : provider가 정한 리소스 타입(🔒). "docker_" = 도커 provider 소속
#   ② "nginx"      : 내가 지은 별명(✏️). 자유롭게 바꿔도 동작 동일
#   ③ name         : 진짜 받아올 도커 이미지 "이름:태그"(값은 ✏️)
resource "docker_image" "nginx" {    # 🔒 resource / 🔒 "docker_image"(타입) / ✏️ "nginx"(별명)
  name         = "nginx:alpine"      # 🔒 name         = ✏️ "nginx:alpine"
  keep_locally = false               # 🔒 keep_locally = ✏️ false  # destroy 시 이미지도 정리
}

# 3-2) 그 이미지로 컨테이너를 띄운다
resource "docker_container" "web" {  # 🔒 resource / 🔒 "docker_container"(타입) / ✏️ "web"(별명)
  # image = docker_image.nginx.image_id  ← "참조" 한 줄이 두 가지를 동시에:
  #   ① 자동 의존성: "이미지 먼저, 컨테이너 나중"이 자동 결정(순서 안 적어도 됨 = 선언형)
  #   ② 값 전달: image_id는 apply 해봐야 아는 값(computed). 이미지 생성 후 그 ID가 채워짐
  image = docker_image.nginx.image_id # 🔒 image = 🔒 docker_image + ✏️ nginx(별명) + 🔒 image_id(속성)
  name  = "tf-tutorial-web"          # 🔒 name = ✏️ "tf-tutorial-web"

  ports {                            # 🔒 ports (하위 블록)
    internal = 80                    # 🔒 internal = ✏️ 80   (컨테이너 내부 포트)
    external = 8080                  # 🔒 external = ✏️ 8080 (내 PC 포트)
  }
}

# 4) output 블록: apply 후 보여줄 결과값
output "url" {                       # 🔒 output / ✏️ "url"(출력 이름)
  value = "http://localhost:8080"    # 🔒 value = ✏️ 값
}
