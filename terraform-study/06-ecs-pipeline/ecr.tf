# ============================================================
# 이 파일: ECR (Elastic Container Registry)
# = 도커 이미지를 보관하는 창고. "AWS판 Docker Hub"라고 보면 된다.
# 그림에서: CodeBuild가 만든 이미지를 여기에 push → ECS가 여기서 pull
# ============================================================

# resource = "이런 게 존재하도록 만들어줘"
#   "aws_ecr_repository" = 리소스 타입(AWS provider가 정한 고정 이름)
#   "app"                = 내가 지은 별명(코드 안에서 부를 이름. 자유롭게 변경 가능)
resource "aws_ecr_repository" "app" {
  name = var.project_name # 창고(저장소) 이름

  # 학습용 옵션: 이미지가 안에 남아 있어도 terraform destroy로 지울 수 있게 함.
  # (실무 기본값은 false → 이미지 있으면 삭제 거부해서 실수 방지)
  force_delete = true

  # 이미지를 push할 때마다 보안 취약점 자동 스캔
  image_scanning_configuration {
    scan_on_push = true
  }
}
