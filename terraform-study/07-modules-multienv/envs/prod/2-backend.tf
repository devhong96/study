# ── 원격 State (S3 backend) ── prod는 key만 다르다 (state 파일 경로 분리)
# dev와 같은 버킷을 쓰되 key가 달라 state가 섞이지 않는다 → 환경 격리.
terraform {
  backend "s3" {
    bucket       = "CHANGE-ME-tfstate-bucket"
    key          = "envs/prod/terraform.tfstate" # ← dev와 다른 경로
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true
  }
}
