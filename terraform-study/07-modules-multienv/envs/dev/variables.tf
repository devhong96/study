variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "my_ip_cidr" {
  type    = string
  default = "0.0.0.0/0" # 실무는 본인 IP/32
}
