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
#   resource "docker_image" "nginx"
#            └─① 타입       └─② 논리명
#   ① docker_image : provider가 정한 리소스 타입. "docker_" = 도커 provider 소속
#                    (실제 도커 엔진 연결은 위 terraform/provider "docker" 블록이 담당)
#   ② "nginx"      : 내가 지은 별명(코드 안 식별자). 자유롭게 바꿔도 동작 동일
#   ③ name         : 진짜 받아올 도커 이미지 "이름:태그" (이게 실체)
#                    nginx = 이미지 이름, alpine = 경량 리눅스 기반 태그(버전)
resource "docker_image" "nginx" {
  name         = "nginx:alpine"
  keep_locally = false # destroy 시 이미지도 정리
}

# 3-2) 그 이미지로 컨테이너를 띄운다
resource "docker_container" "web" {
  # image = docker_image.nginx.image_id
  #   ↑ "참조" 한 줄이 두 가지를 동시에 한다:
  #   ① 자동 의존성: 컨테이너가 이미지의 결과값을 쓰니 "이미지 먼저, 컨테이너 나중"이 자동 결정
  #                  (순서를 코드에 안 적어도 됨 = 선언형. 명령형 docker pull→run 과 반대)
  #   ② 값 전달: image_id는 apply 해봐야 아는 값(computed). 이미지가 만들어진 뒤 그 ID가 채워짐
  #   ※ 문자열 "nginx:alpine"로 박으면 둘이 남남이 되어 순서 보장이 사라짐
  image = docker_image.nginx.image_id
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
