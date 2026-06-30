# [흐름 2/4] 모듈 입력(빈칸) = 호출자(env)가 채워줄 매개변수
#   🔒 variable·type·default·description  /  ✏️ 변수이름·값
variable "project_name" {        # 🔒 variable / ✏️ "project_name"(변수이름)
  type        = string           # 🔒 / 🔒
  description = "리소스 이름/태그 prefix (예: myapp-dev)" # 🔒 / ✏️
  # default 없음 → 호출자가 반드시 줘야 하는 "필수" 입력
}

variable "instance_type" {       # 🔒 / ✏️
  type        = string
  default     = "t3.micro"       # env별로 다르게(dev=micro, prod=small) 덮어씀
  description = "EC2 사양 (dev=micro, prod=small 처럼 환경별로 다르게)"
}

variable "my_ip_cidr" {          # 🔒 / ✏️
  type        = string
  default     = "0.0.0.0/0"      # 실무는 본인 IP/32
  description = "SSH 허용 IP (실무는 본인 IP/32)"
}
