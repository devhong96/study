# Terraform 실습 튜토리얼 (로컬 Docker)

클라우드 비용 0원으로 **문법 + 전체 흐름**만 집중해서 익히는 과정입니다.
각 폴더가 독립된 실습이며, nginx 컨테이너를 띄우며 개념을 체득합니다.

## 사전 준비 (이미 완료됨)
- Terraform v1.15.6 설치됨 (`~/bin/terraform`)
- Docker 실행 중
- 새 터미널이라면 PATH 적용: `export PATH="$HOME/bin:$PATH"`
  (`~/.zshrc`에 등록해뒀으니 터미널 새로 열면 자동 적용)

## 핵심 사이클 (모든 폴더에서 동일)
```
terraform init     # provider(플러그인) 다운로드. 폴더당 최초 1회
terraform plan     # 무엇이 생성/변경/삭제될지 미리보기 (실제 변경 X)
terraform apply    # plan 내용을 실제로 적용
terraform destroy  # 만든 것 전부 삭제 (실습 끝나면 꼭 정리!)
```
> `-auto-approve` 를 붙이면 확인 프롬프트를 건너뜁니다. 학습 땐 떼고 직접 yes 쳐보세요.

## 선언적(declarative) 사고가 핵심
명령형(절차)으로 "이걸 해, 저걸 해"가 아니라,
**"최종 상태가 이래야 해"** 라고 .tf에 적으면
Terraform이 현재 상태(`terraform.tfstate`)와 비교해 **차이만** 적용합니다.
→ 같은 apply를 여러 번 해도 결과가 같음 (멱등성).

## State 파일이 절반이다
apply 후 생기는 `terraform.tfstate` 를 꼭 열어보세요.
Terraform이 "내가 뭘 만들었는지" 기억하는 장부입니다.
이 파일과 실제 인프라를 비교하는 게 plan/apply의 본질.
(실무에선 이 파일을 S3 같은 원격 백엔드에 두고 팀이 공유 — 5단계 참고)

---

## 학습 순서

### 01-hello — 기본 골격
`provider` / `resource` / `output` + 핵심 사이클.
nginx 컨테이너 1개를 8080 포트로 띄움. (이미 실행해봄)
```bash
cd 01-hello && terraform init && terraform plan && terraform apply
# http://localhost:8080 확인 후
terraform destroy
```

### 02-variables — 하드코딩 제거
`variable`(입력) / `terraform.tfvars`(값 주입) / `locals`(내부 상수) / `output`.
환경 분리(dev/prod)의 기초.
```bash
cd 02-variables && terraform init && terraform apply
# 변수 직접 덮어쓰기 실험:
terraform apply -var="external_port=8099"
```

### 03-count-foreach — 반복
같은 리소스를 여러 개. `count`(숫자) vs `for_each`(맵, 실무 권장) 차이를 체감.
```bash
cd 03-count-foreach && terraform init && terraform apply
# var.sites 에서 shop 줄을 지우고 apply → for_each는 shop만 삭제됨(안전)
```

### 04-modules — 재사용
모듈 = 인프라용 함수. `module` 블록으로 호출하고 output을 꺼냄.
```bash
cd 04-modules && terraform init && terraform apply
```

---

## 자주 쓰는 부가 명령
```bash
terraform fmt        # 코드 자동 정렬 (저장 전 습관화)
terraform validate   # 문법 검증
terraform show       # 현재 state 내용 보기
terraform state list # 관리 중인 리소스 목록
terraform output     # output 값만 출력
```

## 실습 후 정리 (중요)
컨테이너가 계속 떠있으니, 끝낸 폴더는 반드시:
```bash
terraform destroy -auto-approve
```

---

## 다음 단계 (이 튜토리얼 이후)
1. **클라우드 provider** (AWS/GCP) — 프리티어로 EC2/VPC 만들기
2. **원격 State** — S3 backend + DynamoDB 락 (팀 협업의 핵심)
3. **data 소스** — 기존 리소스 조회해서 참조
4. **expressions/functions** — `for`, 조건식, `templatefile` 등
5. **import** — 이미 손으로 만든 인프라를 코드로 흡수
6. **CI/CD 연동** — PR에서 plan 자동 실행 (Atlantis 등)

추천 자료: HashiCorp 공식 튜토리얼(developer.hashicorp.com/terraform/tutorials) — 무료, 품질 최고.
```
