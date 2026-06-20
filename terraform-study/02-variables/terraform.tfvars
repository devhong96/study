# 변수 값을 모아두는 파일. terraform이 자동으로 읽음.
# 환경별로 dev.tfvars / prod.tfvars 처럼 나눠서
#   terraform apply -var-file=prod.tfvars
# 형태로 환경을 분리하는 게 실무 패턴.

container_name = "tf-var-web"
external_port  = 8081
image_tag      = "nginx:alpine"
