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
| `database/` | RDB·트랜잭션·격리수준·락·쿼리 | transaction-and-isolation, db-index |
| `distributed/` | 분산 시스템 (분산 락·합의·CAP·일관성) | distributed-lock-and-consensus |
| `architecture/` | 설계·아키텍처 패턴 | saga-pattern |
| `deployment/` | 배포 전략·운영·릴리스 | deploy-strategy, deployment-version-gap |
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
