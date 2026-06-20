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
# count.index 로 0,1,2... 접근. 순서(숫자)로 관리됨.
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
# 각 리소스가 "이름(키)"으로 관리돼서, 중간 항목을 지워도
# 나머지가 재생성되지 않음. count보다 안전.
variable "sites" {
  type = map(number) # 이름 => 외부포트
  default = {
    blog = 9100
    shop = 9101
  }
}

resource "docker_container" "by_foreach" {
  for_each = var.sites
  image    = docker_image.nginx.image_id
  name     = "tf-${each.key}" # each.key=blog, each.value=9100

  ports {
    internal = 80
    external = each.value
  }
}

output "count_names" {
  value = docker_container.by_count[*].name # splat: 전체 추출
}
output "foreach_names" {
  value = { for k, c in docker_container.by_foreach : k => c.name }
}
