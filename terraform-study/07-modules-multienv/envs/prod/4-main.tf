# [흐름 4/4] prod: 같은 webserver 모듈을 "prod 값"으로 호출
#   dev/4-main.tf와 나란히 보면 → source 동일, 값만 다름 = "한 틀, 여러 환경"
#   🔒=예약어  ✏️=내 자유
module "web" {                              # 🔒 module / ✏️ "web"
  source        = "../../modules/webserver" # 🔒 source = ✏️ 경로 (dev와 같은 틀!)
  project_name  = "myapp-prod"              # ✏️ dev는 "myapp-dev" 였음
  instance_type = "t3.small"                # ✏️ dev는 "t3.micro" 였음 (prod는 크게)
  my_ip_cidr    = var.my_ip_cidr
}

output "prod_web_url" {                     # 🔒 output / ✏️ "prod_web_url"
  value = module.web.web_url
}
