# [흐름 4/4] dev: webserver 모듈을 "dev 값"으로 호출 (← 07의 핵심!)
#   prod/4-main.tf와 비교 → source는 같고 project_name·instance_type만 다름 = 환경 복제
#   🔒=예약어  ✏️=내 자유
module "web" {                              # 🔒 module / ✏️ "web"(이 호출의 이름)
  source        = "../../modules/webserver" # 🔒 source = ✏️ 경로(어느 틀을 쓸지)
  project_name  = "myapp-dev"               # ✏️ 모듈 변수에 값 주입 (dev 표시)
  instance_type = "t3.micro"                # ✏️ dev는 작게
  my_ip_cidr    = var.my_ip_cidr            # ✏️ 모듈 변수 = 🔒 var + ✏️ my_ip_cidr
}

output "dev_web_url" {                      # 🔒 output / ✏️ "dev_web_url"
  value = module.web.web_url                # 🔒 module + ✏️ web(별명) + 🔒 web_url(모듈 출력)
}
