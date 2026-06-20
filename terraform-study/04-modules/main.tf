# ============================================================
# Lesson 04 - 모듈(module) 호출
# 목표: 만든 모듈을 재사용해서 여러 환경/서비스 구성
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

# ── 이 파일 = 호출하는 쪽 (루트 모듈) ──────────────────────
# 자식 모듈(modules/webserver)이라는 "틀"을 source로 불러, 빈칸을 채워(인자 주입)
# 여러 번 찍어낸다. = 함수를 인자만 바꿔 여러 번 호출하는 것.

# 공통 자원: 이미지는 root에서 "한 번만" 받아 각 모듈에 image_id로 주입(중복 방지)
resource "docker_image" "nginx" {
  name         = "nginx:alpine"
  keep_locally = false
}

# module 블록 = "함수 호출". source로 어느 틀을 쓸지 지목하고, 빈칸(variable)을 채움.
module "web_a" {
  source        = "./modules/webserver" # ← 어느 모듈(틀)을 쓸지. 로컬 경로(registry/git도 가능)
  name          = "tf-mod-a"            # ┐
  external_port = 9200                  # ├ 모듈의 variable 빈칸을 채우는 인자
  image_id      = docker_image.nginx.image_id # ┘ (root 이미지 ID를 넘김)
}

module "web_b" {                        # 같은 틀을 또 호출 = 재사용 (값만 다름)
  source        = "./modules/webserver"
  name          = "tf-mod-b"
  external_port = 9201
  image_id      = docker_image.nginx.image_id
}
# → root에서 apply 1번이면 web_a/web_b가 하나의 그래프 + 하나의 tfstate로 함께 생성됨

# 모듈의 반환값(output)은 module.<모듈이름>.<출력명> 으로 꺼낸다
output "urls" {
  value = [module.web_a.url, module.web_b.url]
}
