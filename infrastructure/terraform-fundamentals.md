# 테라폼 기초와 큰 그림

> **"원하는 최종 상태"를 코드(`.tf`)에 적으면, 테라폼이 "지금 상태"와 비교해 차이(diff)만 실제 인프라에 적용한다 — 선언형 IaC.**
>
> 빠르게 한 바퀴 훑으며 "전체 그림 + 면접에서 꺼낼 왜"를 잡은 노트.

> 관련 문서: 실습 코드·상세 정리는 [terraform 실습 폴더](../terraform-study/학습정리.md) (01-hello ~ 05-aws-ec2)

---

## 1. 한 문장과 두 사고방식

테라폼은 **선언형(declarative)**이다. "어떻게(how)"가 아니라 **"무엇(what)"**만 적는다.

```
   ① 코드(.tf)        ② 장부(tfstate)        ③ 실제 인프라
  "원하는 상태"   ↔   "내가 아는 상태"    ↔    "진짜 상태"
```

이 셋을 일치시키는 게 테라폼이 평생 하는 일의 전부다.

- **선언형이라 멱등(idempotent).** 같은 코드를 100번 apply해도 결과 동일. 차이가 없으면 아무것도 안 한다.
- **tfstate(장부)가 심장.** 테라폼은 이 파일로 "현재"를 안다. 없으면 아무것도 모른다.

---

## 2. 블록 6종 — 테라폼 코드의 전부

테라폼 코드는 결국 **블록 6종의 조합**이다.

```
terraform { }  → 무엇을 쓸지 (provider 선언·버전)      [메타]
provider  { }  → 어떻게 붙을지 (리전·인증)             [연결]
variable  { }  → 입력 (IN)          ┐
data      { }  → 기존 것 조회 (READ) ├ 본문
resource  { }  → 만들 것 (본체) ★    │
output    { }  → 결과 노출 (OUT)     ┘
       (+ locals = 내부 상수,  module = 본문을 함수로 포장)
```

### 핵심 사이클

| 명령 | 하는 일 | 비유 |
|------|---------|------|
| `init` | provider(플러그인) 다운로드. 폴더당 최초 1회 | `npm install` |
| `plan` | 코드 vs 현재 비교 → 무엇이 바뀔지 미리보기 (변경 X) | `git diff` |
| `apply` | diff를 실제 적용 + tfstate 갱신 | `git commit & push` |
| `destroy` | tfstate에 적힌 것 전부 삭제 | 정리/롤백 |

---

## 3. 자동 의존성 — 명령형과의 결정적 차이 ★

테라폼의 핵심 메커니즘. **순서를 내가 안 적어도 테라폼이 알아서 정한다.**

```hcl
resource "docker_image" "nginx" { name = "nginx:alpine" }

resource "docker_container" "web" {
  image = docker_image.nginx.image_id   # ★ 다른 리소스의 결과값을 "참조"
}
```

이 코드 어디에도 "이미지 먼저 만들어"라는 명령이 **없다.** 그런데도 이미지가 먼저 생성된다.

> 컨테이너가 `docker_image.nginx.image_id`를 **참조**하기 때문. 테라폼은 이걸 보고 "컨테이너는 이미지의 결과값이 필요하다 → 이미지 먼저, 컨테이너 나중"을 **스스로 추론**한다.

```
  docker_image.nginx ──(image_id를 넘겨줌)──▶ docker_container.web
       ① 먼저 생성                              ② 그 다음 생성
```

- **명령형(쉘 스크립트):** `docker pull` → `docker run` 순서를 **내가** 책임짐. 바꾸면 실패.
- **선언형(테라폼):** 순서를 안 적음. **참조가 줄을 세운다.** 코드 작성 순서와 무관.
- **엑셀 비유:** `C1 = A1 + B1` 이라고만 적으면 엑셀이 A1·B1을 먼저 계산하고 C1을 나중에. 순서를 명령한 적 없다.

### 왜 `name`이 아니라 `image_id`인가 (computed attribute)

`image_id`는 이미지를 **실제로 만들어봐야 알 수 있는 값**(생성 후 확정 = computed). 코드 작성 시점엔 비어 있다. 그래서 "이미지 먼저 만들어 값을 알아낸 뒤 → 컨테이너에 채워 넣기"가 강제된다. 만약 `image = "nginx:alpine"`처럼 문자열로 박으면 둘은 **남남**이 되어 순서 보장이 사라진다.

### 내부 원리 — DAG

테라폼은 모든 리소스를 노드로, 참조를 간선으로 놓은 **DAG(방향성 비순환 그래프)**를 만들고 위상 정렬해 순서를 정한다. 서로 참조가 없는 리소스는 **병렬로**(기본 동시성 10) 생성. 순환 참조(A→B→A)는 `Cycle` 에러로 거부 — DAG이기 때문.

---

## 4. 리소스 블록 해부 — 무엇이 정해져 있고 무엇이 내 자유인가

```hcl
resource "docker_image" "nginx" {
#         └─① 타입 ─┘  └─② 논리명─┘
  name         = "nginx:alpine"   # ③ 속성이름 = 값
  keep_locally = false
}
```

| 부분 | 누가 정하나 | 틀리면 |
|------|------------|--------|
| ① **리소스 타입** (`docker_image`) | **provider가 정함** (고정 목록) | `Invalid resource type` (validate 단계) |
| ② **논리명** (`"nginx"`) | **내가 짓는다** (코드 안 식별자) | 자유 — 변수명일 뿐 |
| ③-1 **속성 이름** (`name`, `keep_locally`) | **provider가 정함** (타입별 스키마) | `Unsupported argument` |
| ③-2 **값** (`"nginx:alpine"`) | **내가 채운다** (타입만 맞으면) | 자유 (string/number/bool) |

**핵심:** 테라폼 자체는 `docker_image`가 뭔지 모른다. **provider(kreuzwerker/docker)가 "이런 타입·속성이 있다"는 스키마를 들고 오고**(`init`이 받아오는 이유), 테라폼은 그 스키마와 내 코드를 **대조**한다.

- 타입·속성 **이름**은 provider 사전에 있는 단어만 → 오타는 **도커에 연결도 하기 전에** 해석 단계에서 거부. (cf. 3장의 두 오타 비교: 타입 오타 `docker_imge`는 validate에서, 이미지 이름 오타 `nginx:alpne`는 apply에서 pull 실패)
- 논리명·값은 내 자유.

> **자바 비유:** provider = 라이브러리, 타입 = **클래스**, 속성 = **필드/setter**.
> ```java
> DockerImage nginx = new DockerImage();   // 타입·논리명
> nginx.setName("nginx:alpine");           // 속성이름(정해짐) = 값(내 자유)
> ```
> 클래스·메서드 이름은 라이브러리가 정한 것만 쓰고(오타=컴파일 에러), 값은 자유. ②논리명은 그냥 변수명.

**실무:** 어떤 속성이 있는지는 외우는 게 아니라 **Terraform Registry의 provider 문서**에서 Required/Optional로 확인한다.

---

## 5. 점진적 누적 — 정적에서 실무까지

같은 블록에 살을 붙여가며 정적 → 동적 → 재사용 → 클라우드 실무로 올라간다.

| 단계 | 새로 얹는 것 | 의미 | 백엔드 비유 |
|------|-------------|------|------------|
| **01** | `provider`·`resource`·`output` | 리소스 선언 + 참조=자동 의존성 | Hello World |
| **02** | `variable`·`locals`·`dynamic` | 하드코딩 제거, 값 주입 | 함수 매개변수 / 상수 |
| **03** | `count` vs `for_each` | 같은 리소스 N개 (반복) | `for` 루프 |
| **04** | `module` | 본문을 **함수로 포장**해 재사용 | 함수/클래스 추출 |
| **05** | `data` 조회 + 파일 분리 | 실무 구조 (조회→보안→본체) | 실제 프로젝트 구조 |

### count vs for_each (실무는 for_each 권장)

- `count`: **숫자 인덱스**(0,1,2)로 관리. 중간 항목을 지우면 뒤 항목이 한 칸씩 밀려서 **재생성**됨(index drift). state가 `[0]`,`[1]`을 키로 삼기 때문.
- `for_each`: **키**(blog/shop)로 관리. 중간을 지워도 나머지는 안 건드림 → 안전.

### module = 함수

`variable`(매개변수) 받아 `resource` 만들고 `output`(반환값) 돌려줌. 호출 측은 `module.web_a.url`로 결과를 꺼낸다. 모듈 하나를 web_a/web_b로 여러 번 호출 = 재사용. 하위 폴더 `.tf`는 자동 포함 안 됨 — `module` 블록으로 **직접 지목**해야 하고, 루트 apply 1회로 모든 모듈이 **하나의 그래프 + 하나의 tfstate**로 실행된다.

---

## 6. 버전 제약 `~>` (pessimistic constraint)

**규칙: 명시한 가장 오른쪽 자리까지만 증가 허용, 그 왼쪽은 고정.**

| 제약 | 허용 범위 | 막히는 첫 버전 | 의미 |
|------|-----------|----------------|------|
| `~> 3.0` | `>= 3.0, < 4.0` (3.9 OK) | **4.0** | 마이너 업데이트는 받음 |
| `~> 3.0.0` | `>= 3.0.0, < 3.1.0` (3.0.9 OK) | **3.1.0** | 패치만 받음 (훨씬 좁음) |

- npm의 `^3.0.0`(캐럿)과 같은 의미. `.terraform.lock.hcl`이 `package-lock.json` 역할(해시까지 고정) → **git에 커밋해야** 팀 버전 고정이 의미.
- `terraform { required_version = ">= 1.5" }`는 **테라폼 CLI 자체**의 버전 하한(provider 버전과 별개). 빠뜨리면 팀원이 옛 CLI로 돌리다 깨질 수 있다.

---

## 7. provider 인증 — credential chain

`provider "aws" {}`를 비워둬도 AWS provider(내부 AWS SDK)가 정해진 순서로 자격증명을 자동 탐색한다.

| 순위 | 출처 | 평가 |
|------|------|------|
| 1 | provider 블록에 직접 `access_key`/`secret_key` | ❌ 최악 (git 유출) |
| 2 | 환경변수 `AWS_ACCESS_KEY_ID` / `AWS_PROFILE` | CI/CD에서 흔함 |
| 3 | 공유 파일 `~/.aws/credentials`의 `profile` | 로컬 개발 표준 |
| 4 | **IAM Role** (EC2 instance profile / ECS task role / EKS IRSA) | ✅ 실무 권장 — *키 자체가 없음* |

**고수의 답은 4번:** EC2/ECS 위에서 도는 테라폼이라면 인스턴스에 붙은 IAM Role을 통해 **임시 자격증명을 메타데이터 서비스에서 자동으로** 받는다. 키 파일이 없으니 유출될 게 없다.

---

## 8. data vs resource (실무 진입점)

- `resource` = **만든다.** apply 시 생성, destroy 시 삭제 — 테라폼이 생명주기를 소유.
- `data` = **조회만 한다.** 기존에 존재하는 것을 읽어올 뿐, 생성·삭제하지 않는다. destroy해도 안 지워진다.

```hcl
data "aws_ami" "amazon_linux" { most_recent = true; owners = ["amazon"] }  # 조회
resource "aws_instance" "web" { ami = data.aws_ami.amazon_linux.id }        # 그걸 참조해 생성
```

AMI ID는 리전마다 다르고 수시로 바뀌므로 하드코딩 금지 → **동적 조회.** 이 data가 아래 리소스 참조의 "뿌리"가 된다.

---

## 9. 팀/실무로 확장 (다음 스텝)

| 추가할 것 | 왜 |
|----------|-----|
| **원격 State** (S3 backend + 락) | 팀 공유·동시 apply 방지·유실 방지. **혼자 학습 vs 팀 실무를 가르는 결정적 차이** |
| **module 추출** | 반복 구성 재사용 (network/db/server 분리) |
| **dev/prod tfvars 분리** | 같은 코드 + 다른 값 → 환경 복제 |
| **plan을 PR 리뷰** | "뭐가 바뀌는지" 코드리뷰처럼 검증 |
| **CI/CD 연동** | 사람이 직접 apply 안 함. 승인 기반 자동화 |

---

## 🔗 참고 자료
- HashiCorp 공식 튜토리얼 — developer.hashicorp.com/terraform/tutorials (무료, 1차 자료)
- Terraform Registry — registry.terraform.io (provider·module 출처)
- 실습 코드: [terraform-study/](../terraform-study/) 01-hello ~ 05-aws-ec2

## 🌱 심화 키워드
- **원격 State (S3 backend + DynamoDB/S3 native 락)** — 팀 협업의 핵심, state 동시 변경 방지
- **State 조작 (`import` / `state mv` / `state rm`)** — 손으로 만든 인프라 흡수, 리팩터링
- **count index drift** — 중간 항목 삭제 시 재생성 문제, for_each로 회피
- **pessimistic version constraint (`~>`)** — 버전 잠금 전략
- **credential chain / IAM Role** — 키 없는 인증, 임시 자격증명

## ❓ 남은 질문
1. 원격 State에서 **락(lock)**은 정확히 어느 시점에 잡히고, 동시 apply 충돌을 어떻게 막나? (S3 native locking vs DynamoDB)
   → **답:** plan/apply가 state를 쓰기 시작할 때 락을 잡고 끝나면 푼다. 락이 걸린 동안 다른 apply는 대기·실패한다. DynamoDB 락테이블이 전통적 방식이고, S3 네이티브 락(`use_lockfile`, TF 1.10+)은 별도 테이블 없이 S3만으로 잠근다.
2. tfstate에 **민감정보(비밀번호·키)가 평문**으로 들어가는데 실무에선 어떻게 보호하나? (원격 backend 암호화·접근제어)
   → **답:** 로컬에 두지 말고 저장 암호화(S3 SSE)·전송 암호화·엄격한 IAM 접근제어가 되는 원격 backend에 둔다. 근본적으론 민감값을 Vault·Secrets Manager에서 런타임에 주입해 state 노출 자체를 줄인다.
3. `data` 소스는 **언제 조회**되나? (plan 시점 vs apply 시점, 그 결과가 plan diff에 주는 영향)
   → **답:** 원칙적으로 **plan 시점**에 조회돼 그 값으로 diff를 만든다. 단 의존하는 값이 apply 때 결정(known after apply)되면 조회가 apply로 미뤄지고, 그동안 그 data에 의존한 리소스는 plan에서 "알 수 없음"으로 표시된다.
