# ============================================================
# Lesson 03 - 반복: count / for_each
# 목표: 같은 리소스를 여러 개 만들기 (백엔드의 for문 감각)
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

resource "docker_image" "nginx" {    # 🔒 resource / 🔒 "docker_image" / ✏️ "nginx"
  name         = "nginx:alpine"      # 🔒 / ✏️
  keep_locally = false               # 🔒 / ✏️
}

# ── 방법 A) count: 단순히 N개 만들기 ───────────────────────
# count.index 로 0,1,2... 접근. state가 "순번"([0],[1])으로 관리됨.
# ⚠ index drift: 가운데를 지우면 뒤 항목이 당겨져 순번 어긋남 → 멀쩡한 뒤 리소스 재생성
#   ∴ count는 "그냥 N개 똑같이" 또는 0/1 토글(count = var.enabled ? 1 : 0)에만 권장
resource "docker_container" "by_count" { # 🔒 resource / 🔒 "docker_container" / ✏️ "by_count"
  count = 2                          # 🔒 count(반복 키워드) = ✏️ 2 (개수)
  image = docker_image.nginx.image_id # 🔒 image = 🔒 docker_image + ✏️ nginx + 🔒 image_id
  name  = "tf-count-${count.index}"  # 🔒 name = ✏️ 값 (🔒 count.index = 0,1,2...)

  ports {                            # 🔒 ports
    internal = 80                    # 🔒 / ✏️
    external = 9000 + count.index    # 🔒 external = ✏️ 식 (🔒 count.index)
  }
}

# ── 방법 B) for_each: 키-값 맵으로 만들기 (실무 권장) ────────
# state가 "키"(["blog"],["shop"])로 관리됨. each.key / each.value 로 접근.
# ✅ 중간을 지워도 키가 그대로라 나머지는 손 안 댐 → index drift 없음
variable "sites" {                   # 🔒 variable / ✏️ "sites"(변수이름)
  type = map(number)                 # 🔒 type = 🔒 map(number)  (이름 => 외부포트)
  default = {                        # 🔒 default = ✏️ 맵 값 ↓
    blog = 9100                      # ✏️ blog = ✏️ 9100  (맵 키·값 모두 내 자유)
    shop = 9101                      # ✏️ shop = ✏️ 9101
  }
}

resource "docker_container" "by_foreach" { # 🔒 resource / 🔒 "docker_container" / ✏️ "by_foreach"
  for_each = var.sites               # 🔒 for_each(반복 키워드) = 🔒 var + ✏️ sites
  image    = docker_image.nginx.image_id # 🔒 / 참조
  name     = "tf-${each.key}"        # 🔒 name = ✏️ 값 (🔒 each.key = blog/shop)

  ports {                            # 🔒 ports
    internal = 80                    # 🔒 / ✏️
    external = each.value            # 🔒 external = 🔒 each.value (현재 항목 값)
  }
}

# [*](splat) = 리스트 전 원소에서 같은 속성 한 번에 추출 (count 결과는 리스트)
output "count_names" {               # 🔒 output / ✏️ "count_names"
  value = docker_container.by_count[*].name # 🔒 value = 🔒 docker_container + ✏️ by_count + 🔒 [*].name
}

# { for k, v in ... : k => v.name } = 맵을 돌며 키 보존하고 값만 변환 (for_each 결과는 맵)
output "foreach_names" {             # 🔒 output / ✏️ "foreach_names"
  value = { for k, v in docker_container.by_foreach : k => v.name } # 🔒 for(키워드) / ✏️ k,v(반복변수 이름)
}
