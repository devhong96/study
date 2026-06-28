# ── 재사용 모듈: webserver (자식 모듈 = "틀") ────────────────
# 모듈 = "입력(variable)을 받아 리소스를 만들고 결과(output)를 돌려주는 함수"
# 함수로 치면: webserver(name, external_port, image_id) -> { name, url }
#   ├─ variable = 매개변수(빈칸)  ├─ resource = 본문  └─ output = return
#
# 🔒=예약어(고정)   ✏️=내 자유(변수·별명 이름, 값)
# ────────────────────────────────────────────────────────────

terraform {                          # 🔒 terraform
  required_providers {               # 🔒 required_providers
    docker = {                       # ✏️ docker (provider 로컬 별명)
      source  = "kreuzwerker/docker" # 🔒 / ✏️
      version = "~> 3.0"             # 🔒 / ✏️
    }
  }
}

# 모듈의 입력 파라미터 (= 호출자가 채워줄 빈칸)
variable "name" { type = string }            # 🔒 variable / ✏️ "name"(변수이름) / 🔒 type=🔒 string
variable "external_port" { type = number }   # 🔒 variable / ✏️ "external_port" / 🔒 type=🔒 number
# image_id: 모듈이 이미지를 직접 안 만들고 호출자(root)가 만든 ID만 받음(= 의존성 주입)
variable "image_id" { type = string }        # 🔒 variable / ✏️ "image_id" / 🔒 / 🔒

# 함수 본문: 받은 빈칸(var.*)을 채워 컨테이너를 만든다.
# 논리명 "this": 모듈 안엔 컨테이너가 하나뿐이라 관례로 this.
resource "docker_container" "this" { # 🔒 resource / 🔒 "docker_container"(타입) / ✏️ "this"(별명)
  image = var.image_id               # 🔒 image = 🔒 var + ✏️ image_id(변수이름)
  name  = var.name                   # 🔒 name  = 🔒 var + ✏️ name
  ports {                            # 🔒 ports
    internal = 80                    # 🔒 / ✏️
    external = var.external_port      # 🔒 external = 🔒 var + ✏️ external_port
  }
}

# 모듈의 반환값 (return) — 호출자는 module.<이름>.url 로 꺼냄
output "name" {                      # 🔒 output / ✏️ "name"(출력이름)
  value = docker_container.this.name # 🔒 value = 🔒 docker_container + ✏️ this + 🔒 name
}
output "url" {                       # 🔒 output / ✏️ "url"
  value = "http://localhost:${var.external_port}" # 🔒 value = ✏️ 값(var.external_port 참조)
}
