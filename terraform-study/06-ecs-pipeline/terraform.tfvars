# 값 주입. 환경별로 dev.tfvars / prod.tfvars 로 나누면 환경 분리.
region        = "ap-northeast-2"
project_name  = "tf-ecs-demo"
desired_count = 2

# ★ 본인 GitHub 저장소로 바꾸세요 (형식: 소유자/저장소명)
github_repo   = "owner/my-app"
github_branch = "main"
