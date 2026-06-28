# ============================================================
# Lesson 04 - 모듈(module) 호출
# 목표: 만든 모듈을 재사용해서 여러 환경/서비스 구성
#
# 🔒=예약어(고정)   ✏️=내 자유(별명·값)
# ============================================================

terraform {                          # 🔒 terraform
  required_providers {               # 🔒 required_providers
    docker = {                       # ✏️ docker (provider 로컬 별명)
      source  = "kreuzwerker/docker" # 🔒 / ✏️
      version = "~> 3.0"             # 🔒 / ✏️
    }
  }
}
provider "docker" {}                 # 🔒 provider / ✏️ "docker"

# ── 이 파일 = 호출하는 쪽 (루트 모듈) ──────────────────────
# 자식 모듈(modules/webserver)이라는 "틀"을 source로 불러 빈칸을 채워(인자) 여러 번 찍어냄.

# 공통 자원: 이미지는 root에서 "한 번만" 받아 각 모듈에 image_id로 주입(중복 방지)
resource "docker_image" "nginx" {    # 🔒 resource / 🔒 "docker_image" / ✏️ "nginx"
  name         = "nginx:alpine"      # 🔒 / ✏️
  keep_locally = false               # 🔒 / ✏️
}

# module 블록 = "함수 호출". source로 어느 틀을 쓸지 지목하고, 빈칸(variable)을 채움.
module "web_a" {                     # 🔒 module / ✏️ "web_a"(이 호출의 이름 — 내가 지음)
  source        = "./modules/webserver"       # 🔒 source(예약 칸) = ✏️ 경로
  name          = "tf-mod-a"                  # ✏️ name(모듈이 정의한 변수 이름) = ✏️ 값
  external_port = 9200                        # ✏️ external_port = ✏️ 9200
  image_id      = docker_image.nginx.image_id # ✏️ image_id = 참조(root 이미지 ID)
  #   ↑ 여기 name/external_port/image_id는 "모듈이 정의한 variable 이름"이라 모듈 쪽에선 정해진 칸,
  #     호출 쪽에서 보면 그 변수에 값을 넘기는 자리. (source 만 테라폼 예약 칸)
}

module "web_b" {                     # 🔒 module / ✏️ "web_b" (같은 틀 재호출, 값만 다름)
  source        = "./modules/webserver" # 🔒 / ✏️
  name          = "tf-mod-b"            # ✏️ / ✏️
  external_port = 9201                   # ✏️ / ✏️
  image_id      = docker_image.nginx.image_id
}
# → root에서 apply 1번이면 web_a/web_b가 하나의 그래프 + 하나의 tfstate로 함께 생성됨

# 모듈의 반환값(output)은 module.<모듈이름>.<출력명> 으로 꺼낸다
output "urls" {                      # 🔒 output / ✏️ "urls"
  value = [module.web_a.url, module.web_b.url] # 🔒 module + ✏️ web_a/web_b(별명) + 🔒 url(출력명)
}
