# ============================================================
# 이 파일: 입력 변수 정의 (값은 terraform.tfvars 에서 주입)
# ============================================================

variable "region" {
  type        = string
  description = "AWS 리전"
  default     = "ap-northeast-2" # 서울
}

variable "instance_type" {
  type        = string
  description = "EC2 사양"
  default     = "t3.micro" # 프리티어 대상 사양 (t2.micro도 가능)
}

variable "project_name" {
  type        = string
  description = "리소스 이름/태그에 붙일 프로젝트명"
  default     = "tf-study"
}

# 누가 SSH로 접속 가능한지 (보안). 0.0.0.0/0 은 "전 세계 허용" = 위험.
# 실습이라도 본인 IP만 넣는 게 좋다: "1.2.3.4/32"
variable "my_ip_cidr" {
  type        = string
  description = "SSH 허용 IP 대역 (CIDR)"
  default     = "0.0.0.0/0"
}
