# [흐름 3/4] prod 입력 변수 (dev와 동일)
variable "region" {            # 🔒 variable / ✏️ "region"
  type    = string
  default = "ap-northeast-2"
}

variable "my_ip_cidr" {        # 🔒 variable / ✏️ "my_ip_cidr"
  type    = string
  default = "0.0.0.0/0"        # prod는 반드시 본인/회사 IP로 좁히는 게 맞음
}
