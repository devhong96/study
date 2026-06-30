# [흐름 3/4] dev 환경 입력 변수 (값은 terraform.tfvars에서 주입)
#   🔒 variable·type·default  /  ✏️ 변수이름·값
variable "region" {            # 🔒 variable / ✏️ "region"
  type    = string             # 🔒 / 🔒
  default = "ap-northeast-2"    # 🔒 / ✏️
}

variable "my_ip_cidr" {        # 🔒 variable / ✏️ "my_ip_cidr"
  type    = string             # 🔒 / 🔒
  default = "0.0.0.0/0"        # 🔒 / ✏️ (실무는 본인 IP/32)
}
