# ── 재사용 모듈: webserver ──────────────────────────────────
# 모듈 = "입력(variable)을 받아 리소스를 만들고 결과(output)를 돌려주는 함수"
# 이 폴더 자체가 하나의 모듈.

terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

# 모듈의 입력 파라미터
variable "name" { type = string }
variable "external_port" { type = number }
variable "image_id" { type = string } # 이미지는 호출자가 넘겨줌(중복 다운로드 방지)

resource "docker_container" "this" {
  image = var.image_id
  name  = var.name
  ports {
    internal = 80
    external = var.external_port
  }
}

# 모듈의 반환값
output "name" {
  value = docker_container.this.name
}
output "url" {
  value = "http://localhost:${var.external_port}"
}
