# ── 재사용 모듈: webserver (자식 모듈 = "틀") ────────────────
# 모듈 = "입력(variable)을 받아 리소스를 만들고 결과(output)를 돌려주는 함수"
# 이 폴더 자체가 하나의 모듈. = 붕어빵 틀 1개 (모양 같고 속은 인자로 결정)
#
# 함수로 치면:
#   webserver(name, external_port, image_id) -> { name, url }
#   ├─ variable = 매개변수(빈칸, 밖에서 채워줌)
#   ├─ resource = 함수 본문(실제로 만드는 것)
#   └─ output   = return(결과 돌려주기)

terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

# 모듈의 입력 파라미터 (함수의 매개변수 = 밖에서 채워줄 "빈칸")
variable "name" { type = string }
variable "external_port" { type = number }
# image_id: 모듈이 이미지를 직접 안 만들고 호출자(root)가 만든 ID만 받음.
#   → 모듈을 여러 번 불러도 이미지 리소스가 중복되지 않음(공통 자원은 바깥에서 1번 = 의존성 주입)
variable "image_id" { type = string }

# 함수 본문: 받은 빈칸(var.*)을 채워 컨테이너를 만든다.
# 논리명 "this": 모듈 안엔 컨테이너가 하나뿐이라 관례로 this. 모듈을 web_a/web_b로
#   여러 번 불러도 각 호출이 별도 인스턴스라 충돌 안 함(module.web_a.* / module.web_b.*로 구분)
resource "docker_container" "this" {
  image = var.image_id
  name  = var.name
  ports {
    internal = 80
    external = var.external_port
  }
}

# 모듈의 반환값 (return) — 호출자는 module.<이름>.url 로 꺼냄
output "name" {
  value = docker_container.this.name
}
output "url" {
  value = "http://localhost:${var.external_port}"
}
