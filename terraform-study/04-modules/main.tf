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

# 이미지는 root에서 한 번만 받아서 각 모듈에 주입
resource "docker_image" "nginx" {
  name         = "nginx:alpine"
  keep_locally = false
}

# module 블록: 위에서 만든 모듈을 "함수 호출"하듯 사용
module "web_a" {
  source        = "./modules/webserver" # 로컬 경로. (registry/git도 가능)
  name          = "tf-mod-a"
  external_port = 9200
  image_id      = docker_image.nginx.image_id
}

module "web_b" {
  source        = "./modules/webserver"
  name          = "tf-mod-b"
  external_port = 9201
  image_id      = docker_image.nginx.image_id
}

# 모듈의 output 은 module.<이름>.<출력명> 으로 꺼냄
output "urls" {
  value = [module.web_a.url, module.web_b.url]
}
