# ============================================================
# 이 파일: output = apply가 끝난 뒤 화면에 보여줄 결과값
# "이 인프라를 쓰려면 알아야 할 정보"만 골라서 노출한다.
# ============================================================

# 브라우저로 접속할 주소. aws_lb.app 리소스가 만들어진 뒤 생기는 dns_name을 가져옴.
output "alb_url" {
  description = "서비스 접속 주소"
  value       = "http://${aws_lb.app.dns_name}"
}

# 도커 이미지를 push할 대상 주소 (buildspec.yml이 이 값을 환경변수로 받아 사용)
output "ecr_repository_url" {
  description = "도커 이미지 push 대상"
  value       = aws_ecr_repository.app.repository_url
}

# 만들어진 파이프라인 이름
output "pipeline_name" {
  value = aws_codepipeline.pipeline.name
}

# GitHub 연결의 ARN(고유 식별자).
# 주의: apply 후 AWS 콘솔에서 이 연결을 "수동 승인"해야 작동한다(아래 pipeline.tf 참고).
output "github_connection_arn" {
  description = "apply 후 콘솔에서 이 연결을 수동 승인해야 함 (PENDING→AVAILABLE)"
  value       = aws_codestarconnections_connection.github.arn
}
