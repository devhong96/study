# Lesson 06 - ECS 컨테이너 CI/CD 파이프라인

> `git push` 한 번으로 **빌드 → 이미지 저장 → 배포**가 자동으로 흐르는 인프라를 테라폼으로 정의.

## 흐름

```
 개발자 ─git push─▶ GitHub
                      │ (CodeStar Connection)
                      ▼
   ┌──────────────── CodePipeline ────────────────┐
   │  ① Source  ─▶  ② Build       ─▶  ③ Deploy     │
   │   코드 인출     (CodeBuild)        (ECS)        │
   └─────────────────│──────────────────│──────────┘
                     │ docker build      │ 새 이미지로
                     │ + push            │ 롤링 배포
                     ▼                   ▼
                  [ECR] ──── pull ──▶ [ECS Service]
                 이미지 저장소        (Fargate Task들)
                                          │
                                          ▼
                                       [ALB] ─▶ 사용자
```

## 파일 구성 (관심사별 분리)

| 파일 | 그림의 박스 | 핵심 리소스 |
|------|------------|-------------|
| `provider.tf` | — | provider, 계정 조회 |
| `variables.tf` / `terraform.tfvars` | — | 입력값 |
| `network.tf` | (네트워크) | default VPC 조회, 보안그룹 2개(ALB/ECS) |
| `ecr.tf` | **ECR** | `aws_ecr_repository` |
| `alb.tf` | **ALB** | LB + Target Group + Listener |
| `iam.tf` | (권한) | ECS/CodeBuild/CodePipeline Role |
| `ecs.tf` | **ECS** | Cluster + Task Definition + Service |
| `pipeline.tf` | **CodeBuild/CodePipeline** | S3, GitHub 연결, 빌드, 파이프라인 |
| `outputs.tf` | — | ALB URL, ECR URL 등 |
| `buildspec.yml` | (앱 저장소에 둘 파일) | 도커 빌드 명세 |

## 참조 = 설계 순서

```
ECR ─▶ Task Definition ─▶ ECS Service ─▶ (ALB Target Group)
        보안그룹: ALB ─▶ ECS (ALB 출처만 허용)
        IAM Role: 각 서비스가 키 없이 권한 행사
```

## 실행 (주의: 실제 AWS 과금 + 사전 준비 필요)

```bash
terraform init
terraform validate     # 인증 없이 문법/참조 검증 (여기까지가 학습 목표)
# 실제 배포하려면 ↓ (과금 발생)
terraform apply
# apply 후: 콘솔에서 CodeStar GitHub 연결을 "수동 승인"(PENDING→AVAILABLE)
# 그리고 앱 저장소 루트에 buildspec.yml + Dockerfile 이 있어야 빌드됨
terraform destroy      # 끝나면 반드시 정리
```

## 학습 포인트
- **그림의 모든 박스가 테라폼 리소스** — 파이프라인 자체를 코드로 관리(IaC).
- **참조가 곧 순서**: 01에서 본 자동 의존성이 ECR→TaskDef→Service→ALB로 확장.
- **IAM Role = 키 없는 권한**(05 credential chain): 각 서비스가 `assume_role`로 임시 권한.
- **도구 간 소유권 분리**: 배포는 CodePipeline이 하므로 ECS Service의 `task_definition` 변경은 `lifecycle.ignore_changes`로 테라폼이 무시.
- **`jsonencode`**: 컨테이너 정의 같은 JSON 구조를 HCL로 쓰고 변환.
