# study/ — 학습 정리 인덱스

백엔드 개발자 관점의 학습 노트 저장소.
학습 세션 마지막에 **"정리해줘"** 하면 AI가 이 분류 체계에 맞춰 `.md`로 정리해 넣는다.

> 📄 [`CONVENTIONS.md`](CONVENTIONS.md) — 노트 작성·로그 기록 규칙 · 📆 [`LOG.md`](LOG.md) — 날짜별 학습 로그(연 → 월 → 일)

---

## 분류 체계

| 폴더 | 무엇을 담나 | 현재 노트 |
|------|------------|-----------|
| `java/` | 자바 언어 기능·문법 | java-generics |
| `spring/` | 스프링 프레임워크 (DI·AOP·트랜잭션·비동기 등) | spring-async-event-listener, transactional-deep-dive |
| `jpa/` | JPA·ORM (영속성 컨텍스트·N+1·OSIV·성능·MyBatis 비교) | persistence-context-and-n-plus-one, second-level-cache, em-threadlocal-transaction, association-mapping-owner, optimistic-pessimistic-lock, jpa-vs-mybatis |
| `internals/` | OS·동시성·JVM 내부 (프로세스/스레드/메모리/스레드풀/힙) — 서로 촘촘히 링크됨 | process-thread-basics, process-thread-memory, thread-pool, multicore-memory, jvm-heap-metaspace, sync-async-blocking-nonblocking, context-switching |
| `database/` | RDB·트랜잭션·격리수준·락·쿼리 | transaction-and-isolation, db-index, index-random-io-and-covering |
| `distributed/` | 분산 시스템 (분산 락·합의·CAP·일관성) | distributed-lock-and-consensus |
| `architecture/` | 설계·아키텍처 패턴 | saga-pattern |
| `deployment/` | 배포 전략·운영·릴리스 | deploy-strategy, deployment-version-gap |
| `infrastructure/` | IaC·인프라 자동화 (Terraform 등) | terraform-fundamentals, iac-scope-and-boundaries, api-gateway-vs-load-balancer |
| `etc/` | 분류 전 임시 / 잡다 (CS 기초·인코딩 등) | base64 |

## 앞으로 늘어날 만한 폴더 (백엔드)

필요해지면 그때 만든다. 미리 빈 폴더를 두지 않는다.

- `network/` — HTTP·TCP/IP·TLS·로드밸런싱
- `messaging/` — Kafka·RabbitMQ·이벤트 기반
- `cache/` — Redis·캐시 전략·일관성
- `observability/` — 로깅·메트릭·트레이싱·모니터링
- `security/` — 인증/인가·암호화·취약점

---

## 문서

- [`CONVENTIONS.md`](CONVENTIONS.md) — 노트 파일 규칙, 학습 로그 형식, "커밋"/"정리" 트리거
- [`LOG.md`](LOG.md) — 날짜별 학습 로그 (연 → 월 → 일, 최신 위)
- [`../agents/study/AGENTS.md`](../agents/study/AGENTS.md) — AI 학습 세션 워크플로 전체
