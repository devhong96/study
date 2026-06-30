# ── 모듈 입력(빈칸) = 호출자(env)가 채워줄 매개변수 ──
variable "project_name" {
  type        = string
  description = "리소스 이름/태그 prefix (예: myapp-dev)"
}

variable "instance_type" {
  type        = string
  default     = "t3.micro"
  description = "EC2 사양 (dev=micro, prod=small 처럼 환경별로 다르게)"
}

variable "my_ip_cidr" {
  type        = string
  default     = "0.0.0.0/0"
  description = "SSH 허용 IP (실무는 본인 IP/32)"
}
