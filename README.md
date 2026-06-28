# study/ — 학습 정리 인덱스

백엔드 개발자 관점의 학습 노트 저장소.
학습 세션 마지막에 **"정리해줘"** 하면 AI가 이 분류 체계에 맞춰 `.md`로 정리해 넣는다.
(작성 규칙은 상위 [`../AGENTS.md`](../AGENTS.md) 5장 참고)

---

## 분류 체계

| 폴더 | 무엇을 담나 | 현재 노트 |
|------|------------|-----------|
| `java/` | 자바 언어 기능·문법 | java-generics |
| `spring/` | 스프링 프레임워크 (DI·AOP·트랜잭션·비동기 등) | spring-async-event-listener, transactional-deep-dive |
| `jpa/` | JPA·ORM (영속성 컨텍스트·N+1·OSIV·성능) | persistence-context-and-n-plus-one, second-level-cache, em-threadlocal-transaction, association-mapping-owner, optimistic-pessimistic-lock |
| `internals/` | OS·동시성·JVM 내부 (프로세스/스레드/메모리/스레드풀/힙) — 서로 촘촘히 링크됨 | process-thread-basics, process-thread-memory, thread-pool, multicore-memory, jvm-heap-metaspace, sync-async-blocking-nonblocking |
| `database/` | RDB·트랜잭션·격리수준·락·쿼리 | transaction-and-isolation, db-index, index-random-io-and-covering |
| `distributed/` | 분산 시스템 (분산 락·합의·CAP·일관성) | distributed-lock-and-consensus |
| `architecture/` | 설계·아키텍처 패턴 | saga-pattern |
| `deployment/` | 배포 전략·운영·릴리스 | deploy-strategy, deployment-version-gap |
| `infrastructure/` | IaC·인프라 자동화 (Terraform 등) | terraform-fundamentals |
| `etc/` | 분류 전 임시 / 잡다 (CS 기초·인코딩 등) | base64 |

## 앞으로 늘어날 만한 폴더 (백엔드)

필요해지면 그때 만든다. 미리 빈 폴더를 두지 않는다.

- `network/` — HTTP·TCP/IP·TLS·로드밸런싱
- `messaging/` — Kafka·RabbitMQ·이벤트 기반
- `cache/` — Redis·캐시 전략·일관성
- `observability/` — 로깅·메트릭·트레이싱·모니터링
- `security/` — 인증/인가·암호화·취약점

---

## 규칙

- 파일명: **kebab-case 영어** (`redis-cache-strategy.md`).
- 관련 노트끼리 상단에 `> 관련 문서: [제목](상대경로)` 로 링크. **상대경로 주의** — 다른 폴더면 `../폴더/파일.md`.
- 새 폴더를 만들면 위 표에 **한 줄 추가**.
- 한 노트가 두 분야에 걸치면, 주 분야에 두고 다른 쪽에서 링크로 연결.

---

## 학습 로그

> **"커밋"** 하면 그날 공부한 주제를 여기 기록한다. 최신 날짜가 위.
> 형식: `### YYYY-MM-DD:주제` (날짜와 주제는 콜론으로 붙임, 공백 없이) → 그 아래 `- 소주제`. (규칙은 [`../AGENTS.md`](../AGENTS.md) 5장)

### 2026-06-29:테라폼 05 EC2 심화 + 예약어 구분 + ECS 파이프라인
- 계정 연결: `aws configure` → `~/.aws/credentials`, 코드엔 region만(키 분리), credential chain
- variables.tf(빈칸 정의) vs terraform.tfvars(값 주입): 같은 코드+다른 tfvars=환경 복제, tfvars가 default 덮어씀
- 예약어(🔒) vs 자유(✏️) 판별: 블록키워드·타입(첫 따옴표)·=왼쪽 칸·string/true/var/data=고정 / 두번째 따옴표 별명·=오른쪽 값·tags 키=자유 ("바꿔도 알아들으면 ✏️, 에러나면 🔒")
- 01~05 main.tf에 🔒/✏️ 인라인 주석 / heredoc 시작줄(`<<-EOF`)엔 주석 못 붙임(validate가 잡아냄)
- data 조회(AMI=OS이미지, VPC=네트워크) / security group(ingress·egress, 포트, cidr, SSH는 내 IP만·HTTP 전체=최소권한)
- 06 신규: ECS CI/CD 파이프라인(CodePipeline→CodeBuild→ECR→ECS→ALB)을 테라폼으로 작성 + validate 통과

### 2026-06-23:인덱스 랜덤 I/O·풀스캔 개념 재정리 (문답)
- 랜덤 I/O 근원 재확인: 보조 인덱스 leaf=(컬럼값+PK) 컬럼순 vs 테이블 PK순 → 2번 탐색 때 점프. 느린 건 ②테이블 재방문(① 인덱스 탐색은 email순 정렬이라 순차·빠름)
- "인덱스를 PK순으로 정렬하면?" → email 검색이 풀스캔 돼 인덱스 의미 상실. **한 데이터는 한 순서로만 정렬 가능**(트레이드오프). 인덱스 전체 ≠ 이번 쿼리 결과 PK만 재정렬=MRR
- **커버링이면 4장 선택도 역전(~25%)이 깨짐**: random이 없어 선택도 무관하게 인덱스 유리. 100% 극단에도 index full scan vs full table scan은 크기로 갈려 날씬한 인덱스가 이김 (단 커버링 인덱스가 뚱뚱하면 이점↓)
- 복합 인덱스 선두 컬럼 정렬 규칙 곁가지: `(country,city)`에서 WHERE에 선두 country 없이 city만이면 인덱스 못 탐(성 모르고 이름만으로 전화번호부 찾기)

### 2026-06-21:테라폼 실습 코드 분석 (01~05)
- 리소스 블록 해부: ①타입(provider 고정) ②논리명(자유) ③속성이름(고정)·값(자유), provider 스키마와 대조
- 자동 의존성 심화: 참조가 순서를 만듦(DAG), image_id=computed(plan은 `known after apply`→apply 확정)
- dynamic 부품 4개(컨테이너 1개, 블록만 반복) / var(밖에서 주입)·local(안에서) 차이·주입 우선순위
- count(순번키→index drift 재생성) vs for_each(키 기반 안전), splat `[*]` / for식
- module=함수(정의=틀, 호출=root), image_id 주입=의존성주입, `this` 논리명
- 05 파일분리 관례, data(조회=SELECT, plan 시점) vs resource, security group(보안 먼저), user_data, credential chain
- 01~05 main.tf 전체 주석 보강 / 오타 실험: `docker_imge`=Invalid resource type(validate) vs 이미지이름 오타=apply pull 실패

### 2026-06-20:테라폼 기초와 큰 그림
- 선언형·멱등 + tfstate(장부): 코드↔state↔실제 인프라 세 가지 일치가 전부
- 블록 6종(terraform/provider/variable/data/resource/output) + 사이클(init/plan/apply/destroy)
- 자동 의존성: 참조(`타입.이름.속성`)가 순서를 세움 → DAG 위상정렬·병렬, computed attribute(image_id), 명령형 vs 선언형
- 점진 누적 01→05: 정적→변수→반복(count vs for_each, index drift)→module(함수)→data 조회+클라우드
- 버전 제약 `~>`: 오른쪽 끝 자리까지만 증가 허용(`~>3.0`=3.x, `~>3.0.0`=3.0.x), required_version은 CLI 버전
- provider credential chain: 코드 직접<환경변수<~/.aws<IAM Role(키 없는 임시자격증명, 실무 권장)
- data(조회, destroy 안 됨) vs resource(생성·삭제 소유)
- 01-hello/main.tf에 required_version 추가

### 2026-06-19:인덱스의 랜덤 I/O와 커버링
- 순차 vs 랜덤 읽기: 페이지 단위 I/O, random은 흩어진 페이지 점프라 비쌈(대략 ×4 추정치)
- 보조 인덱스 조회가 random인 이유: leaf는 (컬럼값+PK)를 **컬럼순**, 테이블 행은 **PK순** 저장 → 두 정렬 어긋남 → 2번 탐색 시 흩어진 페이지로 점프
- MRR: 결과 PK를 PK순 재정렬해 random→sequential, 단 "테이블로 나가는 것" 자체는 못 없앰(교차점만 미룸)
- 풀스캔 역전: 선택도(**행** 기준) ~20~25%↑면 어차피 거의 모든 페이지 만짐 + random 단가 비쌈 → 풀스캔이 쌈
- 헷갈린 두 축 정리: 30%=행(선택도, 실행 시) vs 커버링=열/폭(설계 시). 인덱스는 행 수는 테이블과 같고 컬럼만 추려 날씬
- 커버링은 구조 비교(스키마)로 실행 전 판단 / WHERE 컬럼=걸러내기(없으면 풀스캔), SELECT 컬럼=커버링 여부(다 있으면 random read 소멸)

### 2026-06-14:JPA 영속성 컨텍스트 심화
- 2차 캐시: 캐시 3층 구조, 상태 스냅샷 저장, 동시성 전략, 쿼리 캐시 함정, 쓰면 안 되는 경우
- EM·ThreadLocal·트랜잭션: dirty checking 스냅샷, 주입 EM은 싱글톤 프록시, ThreadLocal 캐비닛/서랍 구조, @Async가 깨지는 이유, EM·컨텍스트·트랜잭션 관계, remove() 철칙
- OSIV: 컨텍스트 수명(요청~응답 끝), 커넥션 점유 메커니즘(TX 끝나도 응답까지 쥠), OFF면 서비스에서 fetch join/@EntityGraph+DTO, "엔티티=영속·DTO=표현" 한 원칙이 LazyInit·직렬화 N+1·API-DB 결합을 동시 해결

### 2026-06-14:JPA 연관관계 & 동시성 심화
- 연관관계 매핑: mappedBy=주인 아닌 쪽(거울), "객체 참조 둘 vs FK 하나", 거울은 DB 컬럼 없음, 주인만 세팅 시 DB는 저장되나 같은 TX 객체엔 stale, 편의 메서드는 "정합성 보험"(같은 TX 재사용·cascade에서 필요), @ManyToOne 단방향이 권장 기본값·양방향은 옵션
- 낙관적 vs 비관적 락: 갱신 분실(Lost Update), 낙관적=@Version·예외→재시도·CAS(WHERE version=?+행 락), 비관적=FOR UPDATE·블로킹, "오류 반환"은 낙관적 / 무조건 비관적은 블로킹으로 커넥션 풀 고갈·데드락, 단순 증감은 원자적 UPDATE

### 2026-06-14:학습 커밋 규칙 셋업
- `study/README.md` 학습 로그 섹션 추가
- `AGENTS.md`에 커밋 규칙(날짜+주제, 긴 주제는 소주제 분리) 추가
- git 저장소 초기화

### 2026-06-14:저장소 구조 정비
- `folder/`를 단일 루트 저장소로 승격 (기존 study 히스토리·원격 계승)
- 트리거 분리: "커밋"=로컬 커밋까지, "정리"=노트 저장+커밋+push까지
- 루트 `README.md` 추가 (저장소 개요·구조·워크플로 — GitHub 랜딩 문서)
