# [흐름 2/4] 원격 State (S3 backend) — dev와 "key만" 다르다!
#   같은 버킷, 다른 key → dev/prod state가 섞이지 않음 = 환경 격리의 핵심
#   🔒=예약어  ✏️=내 자유
terraform {
  backend "s3" {
    bucket       = "CHANGE-ME-tfstate-bucket"       # dev와 동일 버킷 OK
    key          = "envs/prod/terraform.tfstate"    # ✏️ ← dev는 envs/dev/... 였음 (이 한 줄이 격리)
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true
  }
}
