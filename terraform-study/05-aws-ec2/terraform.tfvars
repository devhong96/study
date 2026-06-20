# 변수 값 주입. 환경별로 dev.tfvars / prod.tfvars 로 나눠 쓰면 환경 분리.
region        = "ap-northeast-2"
instance_type = "t3.micro"
project_name  = "tf-study"

# ★ 실제 적용 전 본인 공인 IP로 바꾸세요 (curl ifconfig.me 로 확인)
# my_ip_cidr  = "1.2.3.4/32"
