# ── dev 환경: webserver 모듈을 "dev 값"으로 호출 ──
# 같은 모듈, 다른 인자 → 환경 복제. (prod와 비교해보면 값만 다름)
module "web" {
  source        = "../../modules/webserver"
  project_name  = "myapp-dev"
  instance_type = "t3.micro" # dev는 작게
  my_ip_cidr    = var.my_ip_cidr
}

output "dev_web_url" {
  value = module.web.web_url
}
