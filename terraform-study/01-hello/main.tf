# ============================================================
# Lesson 01 - Hello Terraform (Docker provider)
# 목표: provider / resource / 핵심 사이클(init→plan→apply→destroy) 체득
# ============================================================

# 1) terraform 블록: 이 코드가 어떤 provider(플러그인)를 쓸지 선언
terraform {
  required_version = ">= 1.5" # 테라폼 CLI 자체의 버전 하한 (provider 버전과 별개)

  required_providers {
    docker = {
      source  = "kreuzwerker/docker" # Terraform Registry 주소
      version = "~> 3.0"             # 3.x 버전대 사용 (~> 는 "이 이상 마이너만" 의미)
    }
  }
}

# 2) provider 블록: 실제 대상(여기선 로컬 Docker)에 어떻게 접속할지 설정
provider "docker" {}

# 3) resource 블록: "이런 리소스가 존재하게 해줘" 라고 선언
#    형식: resource "<리소스타입>" "<이름(코드 내 식별자)>" { ... }

# 3-1) nginx 이미지를 받아온다
resource "docker_image" "nginx" {
  name         = "nginx:alpine"
  keep_locally = false # destroy 시 이미지도 정리
}

# 3-2) 그 이미지로 컨테이너를 띄운다
resource "docker_container" "web" {
  image = docker_image.nginx.image_id # ← 다른 리소스 참조 = 자동 의존성 형성
  name  = "tf-tutorial-web"

  ports {
    internal = 80   # 컨테이너 내부 포트
    external = 8080 # 내 PC 포트 (http://localhost:8080)
  }
}

# 4) output 블록: apply 후 보여줄 결과값
output "url" {
  value = "http://localhost:8080"
}
