# ── prod 환경: 같은 webserver 모듈을 "prod 값"으로 호출 ──
# dev/main.tf와 비교 → source는 같고 project_name·instance_type만 다름 = 환경 복제의 핵심
module "web" {
  source        = "../../modules/webserver"
  project_name  = "myapp-prod"
  instance_type = "t3.small" # prod는 조금 크게
  my_ip_cidr    = var.my_ip_cidr
}

output "prod_web_url" {
  value = module.web.web_url
}
