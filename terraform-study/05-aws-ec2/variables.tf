# ============================================================
# 이 파일: 입력 변수 정의 (값은 terraform.tfvars 에서 주입)
# 🔒=예약어(고정)   ✏️=내 자유(변수이름·값)
# 네 블록 모두 같은 틀: variable "✏️이름" { type/description/default(🔒) = 값(✏️) }
# ============================================================

variable "region" {               # 🔒 variable / ✏️ "region"(변수이름)
  type        = string            # 🔒 type        = 🔒 string(타입 키워드)
  description = "AWS 리전"         # 🔒 description = ✏️ "AWS 리전"
  default     = "ap-northeast-2"   # 🔒 default     = ✏️ "ap-northeast-2"  (서울)
}

variable "instance_type" {        # 🔒 variable / ✏️ "instance_type"
  type        = string            # 🔒 / 🔒
  description = "EC2 사양"         # 🔒 / ✏️
  default     = "t3.micro"         # 🔒 / ✏️ (프리티어 대상)
}

variable "project_name" {         # 🔒 variable / ✏️ "project_name"
  type        = string            # 🔒 / 🔒
  description = "리소스 이름/태그에 붙일 프로젝트명" # 🔒 / ✏️
  default     = "tf-study"         # 🔒 / ✏️
}

# 0.0.0.0/0 은 "전 세계 허용" = 위험. 실습이라도 본인 IP만 넣는 게 좋다: "1.2.3.4/32"
variable "my_ip_cidr" {           # 🔒 variable / ✏️ "my_ip_cidr"
  type        = string            # 🔒 / 🔒
  description = "SSH 허용 IP 대역 (CIDR)" # 🔒 / ✏️
  default     = "0.0.0.0/0"        # 🔒 / ✏️
}
