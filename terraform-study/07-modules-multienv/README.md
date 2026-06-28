# Lesson 07 - 모듈 + 멀티환경(dev/prod) + 원격 State

> 혼자 학습으로 도달 가능한 "실무 구조"의 핵심 3종: **재사용 모듈 / 환경 분리 / 원격 State**.

## 구조

```
07-modules-multienv/
├── modules/
│   └── webserver/        ← 재사용 "틀" (05의 EC2+보안그룹을 모듈화)
│       ├── versions.tf   provider 요구사항
│       ├── variables.tf  입력(빈칸)
│       ├── main.tf       data·보안그룹·EC2
│       └── outputs.tf    출력(public_ip 등)
└── envs/
    ├── dev/              ← dev 환경 (루트 모듈, 별도 state)
    │   ├── provider.tf
    │   ├── backend.tf    S3 원격 state (key: envs/dev/...)
    │   ├── main.tf       module "web" 호출 (t3.micro)
    │   ├── variables.tf
    │   └── terraform.tfvars
    └── prod/             ← prod 환경 (같은 모듈, t3.small, key만 다름)
        └── (dev와 동일 구조)
```

## 핵심 3가지

| 개념 | 어떻게 | 왜 |
|------|--------|-----|
| **모듈** | `modules/webserver`를 dev·prod가 `source`로 호출 | 같은 구성 재사용, 한 곳만 고치면 모든 환경 반영 |
| **환경 분리** | `envs/dev`, `envs/prod` 폴더 + 각자 tfvars | 같은 코드 + 다른 값(인스턴스 사양) = 환경 복제 |
| **원격 State** | `backend.tf`의 S3 backend (env별 `key` 다름) | state를 S3에 공유 + 동시 apply 잠금. **dev/prod state 격리** |

## 환경이 어떻게 갈리나

```
            modules/webserver  (틀 1개)
                  │
      ┌───────────┴───────────┐
   envs/dev                envs/prod
   t3.micro                t3.small        ← instance_type만 다름
   key=envs/dev/...        key=envs/prod/...  ← state 경로 분리(섞이지 않음)
```

## 실행 (각 환경 폴더에서)

```bash
cd envs/dev
terraform init      # 모듈 가져오고 S3 backend 연결
terraform apply     # dev 인프라 생성

cd ../prod
terraform init
terraform apply     # prod 인프라 생성 (별도 state)
```

## 학습 포인트
- **루트 모듈 = `terraform`을 실행하는 폴더.** 여기선 `envs/dev`, `envs/prod`가 각각 루트(각자 state 1개).
- **모듈은 provider를 정의하지 않는다.** 루트(env)의 provider를 물려받음. 모듈엔 `required_providers`만(versions.tf).
- **backend 블록은 변수를 못 쓴다**(init 시점 평가). 그래서 bucket/key를 직접 적는다.
- **S3 버킷은 미리 존재해야 한다**(이 코드가 만들지 않음). 보통 "부트스트랩"용 폴더를 먼저 apply.
- `use_lockfile = true` = S3 네이티브 잠금(Terraform 1.10+). 예전엔 DynamoDB 테이블로 잠갔음.
