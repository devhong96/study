# [흐름 2/4] 원격 State (S3 backend) — state를 S3에 두어 팀 공유 + 동시 apply 잠금
#   혼자 학습 vs 팀 실무를 가르는 결정적 차이.
#   ※ 주의:
#     1) backend 블록은 변수를 못 쓴다(init 시점 평가) → 값을 직접 적는다.
#     2) 이 S3 버킷은 "미리" 존재해야 한다(이 코드가 만들지 않음 = chicken-egg).
#     3) 학습 땐 이 블록을 통째로 주석 처리하면 로컬 state로 동작.
#   🔒=예약어  ✏️=내 자유
terraform {                                        # 🔒 terraform
  backend "s3" {                                   # 🔒 backend / ✏️ "s3"(backend 종류)
    bucket       = "CHANGE-ME-tfstate-bucket"      # 🔒 bucket = ✏️ 미리 만든 버킷 이름
    key          = "envs/dev/terraform.tfstate"    # 🔒 key = ✏️ 이 env state 경로 (prod와 다름! → 격리)
    region       = "ap-northeast-2"                # 🔒 = ✏️
    encrypt      = true                            # 🔒 encrypt = 🔒 true (state 암호화)
    use_lockfile = true                            # 🔒 = 🔒 true (S3 네이티브 잠금, TF 1.10+)
  }
}
