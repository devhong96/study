# ============================================================
# Lesson 03 - 반복: count / for_each
# 목표: 같은 리소스를 여러 개 만들기 (백엔드의 for문 감각)
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

resource "docker_image" "nginx" {
  name         = "nginx:alpine"
  keep_locally = false
}

# ── 방법 A) count: 단순히 N개 만들기 ───────────────────────
# count.index 로 0,1,2... 접근. state가 "순번"([0],[1])으로 관리됨.
# ⚠ index drift: 가운데([1])를 지우면 뒤 항목이 한 칸씩 당겨져 순번이 어긋남
#   → 테라폼이 "[1]이 바뀌었다"고 보고 멀쩡한 뒤 리소스를 재생성(다운타임 위험)
#   ∴ count는 "그냥 N개 똑같이" 또는 0/1 토글(count = var.enabled ? 1 : 0)에만 권장
resource "docker_container" "by_count" {
  count = 2
  image = docker_image.nginx.image_id
  name  = "tf-count-${count.index}" # tf-count-0, tf-count-1

  ports {
    internal = 80
    external = 9000 + count.index # 9000, 9001
  }
}

# ── 방법 B) for_each: 키-값 맵으로 만들기 (실무 권장) ────────
# state가 "키"(["blog"],["shop"])로 관리됨. each.key / each.value 로 접근.
# ✅ 중간(["shop"])을 지워도 키가 그대로라 나머지는 손도 안 댐 → index drift 없음
#   ∴ "정체성이 있는" 리소스(서버들·사이트들·유저들)는 for_each 가 정답
variable "sites" {
  type = map(number) # 이름 => 외부포트
  default = {
    blog = 9100
    shop = 9101
  }
}

# - docker_image.nginx.image_id = 타입.논리명.속성 3토막 참조. docker_image.nginx 리소스가 만들어낸 image_id 속성을 가져다 쓴다.
# - image_id는 무엇? 이미지를 실제로 받고 나면 도커가 매기는 고유 ID(sha256 다이제스트 같은 것). 이미지의 "지문"이에요.
# - 왜 name("nginx:alpine")이 아니라 image_id? image_id는 이미지를 실제로 받아봐야 알 수 있는 값(computed attribute). 코드 작성 시점엔 비어 있어요

resource "docker_container" "by_foreach" {
  for_each = var.sites
  image    = docker_image.nginx.image_id
  name     = "tf-${each.key}" # each.key=blog, each.value=9100

  ports {
    internal = 80
    external = each.value
  }
}
# count로 만든 리소스는 리스트처럼 인덱스로 접근됩니다:
# docker_container.by_count[0].name  →  "tf-count-0"
# docker_container.by_count[1].name  →  "tf-count-1"
#
# 이걸 하나하나 쓰는 대신, [*](splat, 별표)가 "모든 원소"를 대신해서 각자의 .name을
# 한 방에 리스트로 뽑습니다:

output "count_names" {
  value = docker_container.by_count[*].name # splat: 전체 추출
}

# { for k, v in docker_container.by_foreach : k => v.name }
# │   └──┬──┘ └──────────┬──────────────┘   └───┬────┘
# │      │               │                       │
# │   ① 각 항목을         ② 이 컬렉션(맵)을      ③ 새 항목: 키=k, 값=v.name
# │      k(키),v(값)에 담아   돌면서
# └─ 바깥이 {} → 결과는 "맵"
output "foreach_names" {
  value = { for k, v in docker_container.by_foreach : k => v.name }
}
