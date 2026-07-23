# IaC의 범위와 경계 — 어디까지 테라폼으로 하나

> **거의 모든 AWS 서비스를 IaC로 "만들" 수 있지만, IaC가 담당하는 건 인프라의 생성·구성·변경(프로비저닝)까지. 앱 배포·운영·데이터는 다른 도구와 역할을 나눈다.**

> 관련 문서: [terraform-fundamentals](terraform-fundamentals.md) · 실습 [terraform-study/](../terraform-study/)

---

## 1. 거의 모든 AWS 서비스를 IaC로 만들 수 있다

AWS provider는 수천 개 리소스 타입을 지원한다. 우리가 본 `aws_instance`·`aws_ecs_service`와 **완전히 같은 `resource "타입" "별명" { ... }` 패턴**이다.

| 영역 | 서비스 | 대표 리소스 |
|------|--------|-------------|
| 컴퓨트 | EC2 / ECS / EKS / Lambda | `aws_instance`, `aws_ecs_service`, `aws_eks_cluster`, `aws_lambda_function` |
| 네트워크 | VPC / ALB·NLB / Route53 / CloudFront | `aws_vpc`, `aws_lb`, `aws_route53_record`, `aws_cloudfront_distribution` |
| DB·캐시 | RDS / Aurora / DynamoDB / ElastiCache | `aws_db_instance`, `aws_rds_cluster`, `aws_dynamodb_table`, `aws_elasticache_replication_group` |
| 메시징 | SQS / SNS / Kinesis / MSK(Kafka) | `aws_sqs_queue`, `aws_sns_topic`, `aws_msk_cluster` |
| 스토리지 | S3 / EFS / EBS | `aws_s3_bucket`, `aws_efs_file_system` |
| 보안 | IAM / Secrets Manager / KMS / WAF | `aws_iam_role`, `aws_secretsmanager_secret`, `aws_kms_key` |

```hcl
# ElastiCache(Redis) — EC2와 똑같은 resource 구조
resource "aws_elasticache_replication_group" "cache" {
  replication_group_id = "myapp-redis"
  node_type            = "cache.t3.micro"
  engine               = "redis"
  num_cache_clusters   = 2
}
```

**한 패턴을 익히면 어떤 서비스든 문서 보고 쓸 수 있다** — 타입 이름과 속성만 다를 뿐 구조는 동일.

---

## 2. "관리"의 경계 — IaC가 하는 것 vs 다른 도구

"관리"를 쪼개야 답이 명확하다. IaC는 **인프라의 뼈대(생성·구성·변경)**를 담당하고, 나머지는 역할을 나눈다.

| 작업 | 담당 도구 | IaC가? |
|------|-----------|--------|
| 인프라 **생성·구성·삭제** (클러스터·DB·네트워크) | **Terraform** | ✅ |
| 구성 **변경** (인스턴스 크기↑, 엔진 버전 업) | **Terraform** | ✅ 코드 고치고 apply |
| 앱 **코드 배포** (새 버전 릴리스) | **CI/CD** (CodePipeline·ArgoCD) | ⚠️ IaC는 "파이프라인 자체"만 만듦, 매 배포는 CI/CD |
| K8s 워크로드 (Pod·Deployment) | **Helm / kubectl / ArgoCD** | ⚠️ EKS 클러스터=IaC, 그 안 앱=별도 |
| **운영** (로그·모니터링·장애 대응) | CloudWatch·운영 도구 | ❌ |
| **데이터** (DB 안의 레코드) | 앱·SQL | ❌ |
| 일회성 작업 ("이 캐시 비워") | CLI·콘솔 | ❌ 명령형 |

**핵심 구분:**
- **IaC = "이런 인프라가 존재해야 한다"** — 선언적, 상태 관리(만들고·바꾸고·지움).
- **운영/배포/데이터 = "지금 이걸 해라"** — 명령형, 런타임. 다른 도구의 몫.

---

## 3. 실무 철학 — "콘솔에서 손대지 마" (drift 방지)

이상적으로는 **모든 인프라를 코드로** 관리한다. 이유:

- 콘솔에서 수동 변경하면 **drift**(코드의 "원하는 상태" ≠ 실제 상태)가 생긴다.
- 다음 `terraform plan`이 그 차이를 감지하고, `apply`가 되돌리거나 충돌한다.

```
"원하는 상태"(코드) ──plan으로 비교──▶ "실제 상태"(AWS)
        누가 콘솔에서 손대면 → plan이 "차이 있음!" → drift
```

- 그래서 리소스에 `ManagedBy = "terraform"` 태그를 붙여 "손대지 말고 코드로 고쳐라"를 표시.
- **현실 운영:** 핵심 인프라는 IaC로, 긴급·실험은 콘솔로 빠르게 → 나중에 `terraform import`로 코드에 흡수.

---

## 4. 도구 역할 분담 (한눈에)

| 도구 | 역할 | 방식 |
|------|------|------|
| **Terraform** | 인프라 프로비저닝(생성·구성) | 선언적, 멀티 클라우드 |
| **CloudFormation** | 〃 (AWS 전용) | 선언적 |
| **Ansible** | 서버 내부 설정·앱 설치 | 명령형·절차적 |
| **Helm/ArgoCD** | K8s 워크로드 배포(GitOps) | 선언적, 앱 레벨 |
| **CI/CD** (CodePipeline 등) | 코드 빌드·배포 오케스트레이션 | 이벤트 기반 |

→ 경계: **Terraform = 인프라 뼈대 / Ansible = 그 위 설정 / Helm·ArgoCD = K8s 앱 / CI/CD = 배포 흐름.**

---

## 🔗 참고 자료
- Terraform AWS Provider 문서 — registry.terraform.io/providers/hashicorp/aws (전 리소스 목록)
- HashiCorp "Terraform vs other tools" 비교 문서

## 🌱 심화 키워드
- **drift / `terraform plan`·`refresh`** — 코드와 실제의 차이 감지
- **`terraform import`** — 손으로 만든 리소스를 코드로 흡수
- **GitOps (ArgoCD/Flux)** — K8s 워크로드를 git으로 선언적 관리 (IaC의 앱배포 버전)
- **Terraform vs Ansible** — 프로비저닝(IaC) vs 설정관리(명령형)
- **Crossplane** — K8s 방식으로 인프라를 관리하는 대안

## ❓ 남은 질문
1. 콘솔에서 인스턴스 타입을 바꾸면 다음 `terraform apply`는 어떻게 반응하나? (drift 처리: 되돌림 vs `ignore_changes`)

   → **답:** plan이 실제(콘솔 변경값)와 코드의 drift를 감지해 기본은 코드 기준으로 **되돌리는** 변경을 제안한다. 코드로 관리하고 싶지 않은 속성은 `lifecycle.ignore_changes`로 제외해 되돌림을 막는다.
2. EKS 클러스터는 Terraform, 그 안 앱(Deployment)은 왜 Helm/ArgoCD로 따로 관리하나? (생성 빈도·생명주기 차이)

   → **답:** 클러스터 같은 인프라는 생성 빈도가 낮고 수명이 길어 Terraform이 맞고, 앱 배포는 하루에도 여러 번 바뀌는 짧은 생명주기라 K8s 네이티브·GitOps(Helm/ArgoCD)가 롤아웃·롤백에 유리하다 — 변경 주기·책임 경계가 달라 도구를 나눈다.
3. `terraform import`로 기존 인프라를 코드화할 때, state엔 들어오지만 `.tf` 코드는 자동 생성 안 되는 이유는? (state vs config)

   → **답:** import는 실제 리소스를 **state에 매핑**만 하고 HCL은 사용자가 직접 써야 한다(state=실제 상태, config=의도라 자동 역생성이 위험). 코드가 없으면 다음 plan이 삭제로 보이며, TF 1.5+의 `import` 블록·`-generate-config-out`이 초안 생성을 돕는다.
