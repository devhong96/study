# ============================================================
# 이 파일: 입력 변수 = "밖에서 바꿔 끼울 수 있는 값"의 목록
# 실제 값은 terraform.tfvars 에서 넣는다. (정의는 여기, 값은 거기)
# variable = 함수의 매개변수라고 생각하면 쉽다.
# ============================================================

# 리전(지역). default가 있으니 따로 안 넣어도 이 값이 쓰인다.
variable "region" {
  type    = string
  default = "ap-northeast-2" # 서울
}

# 모든 리소스 이름 앞에 붙일 접두사. "tf-ecs-demo-alb" 처럼 이름이 만들어짐.
# → 이름 충돌 방지 + 어떤 프로젝트 것인지 식별
variable "project_name" {
  type        = string
  default     = "tf-ecs-demo"
  description = "모든 리소스 이름/태그의 prefix"
}

# 컨테이너 안의 앱이 듣는(listen) 포트. nginx면 80.
variable "container_port" {
  type        = number
  default     = 80
  description = "컨테이너가 listen하는 포트 (예: nginx=80)"
}

# 컨테이너(Task)를 몇 개 띄워 유지할지. 2면 항상 2개가 떠 있도록 ECS가 관리.
variable "desired_count" {
  type        = number
  default     = 2
  description = "ECS Service가 유지할 Task(컨테이너) 개수"
}

# ── 소스 저장소 (CodePipeline의 Source 단계가 코드를 가져올 곳) ──
# "소유자/저장소명" 형식. 예: "devhong96/my-app"
variable "github_repo" {
  type        = string
  default     = "owner/my-app"
  description = "GitHub 저장소 (형식: 소유자/저장소명)"
}

# 어느 브랜치를 배포할지. 보통 main.
variable "github_branch" {
  type    = string
  default = "main"
}
