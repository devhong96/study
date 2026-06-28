# ── 원격 State (S3 backend) ──
# 왜? state(인프라 장부)를 로컬이 아니라 S3에 두어 팀이 공유하고, 동시 apply를 막는다.
# 혼자 학습 vs 팀 실무를 가르는 결정적 차이.
#
# ※ 주의 2가지:
#   1) backend 블록은 변수를 못 쓴다(init 시점에 평가됨) → 값을 직접 적는다.
#   2) 이 S3 버킷은 "미리" 존재해야 한다(이 코드가 만들지 않음, chicken-egg).
#      → 보통 버킷 생성용 작은 폴더를 먼저 apply하거나 콘솔에서 만든다.
#
# 학습 단계에선 이 블록을 주석 처리하면 로컬 state로 동작(init/validate 가능).
terraform {
  backend "s3" {
    bucket       = "CHANGE-ME-tfstate-bucket"      # 미리 만든 S3 버킷 이름
    key          = "envs/dev/terraform.tfstate"    # 이 환경 state가 저장될 경로
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true                            # S3 네이티브 잠금(동시 apply 방지, Terraform 1.10+)
  }
}
