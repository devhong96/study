# 260715 : Lettuce보다 Redisson을 선택할 수 있는 이유는 무엇인가요?

Lettuce보다 Redisson을 선택할 수 있는 이유는 무엇인가요?

이 질문은 Redis client를 단순 연결 도구로 보는지, 아니면 분산락 같은 고수준 기능의 안정성까지 고려하는지 확인하기 좋습니다.

좋은 답변에는 이런 흐름이 들어가면 좋습니다.

- Lettuce는 Redis command를 직접 다루기 좋은 client이고, `SET NX PX` 같은 명령으로 lock을 직접 구현할 수 있습니다.
- 하지만 직접 구현하면 lock 획득, TTL 설정, 소유자 검증, 안전한 해제, 재시도, 대기 방식 등을 모두 직접 신경 써야 합니다.
- Redisson은 `RLock` 같은 분산락 abstraction을 제공해서 lock 사용 코드를 더 단순하게 만들 수 있습니다.
- 또한 watchdog, pub/sub 기반 대기, lease time 관리 같은 기능을 제공해 직접 구현보다 운영 안정성을 높일 수 있습니다.
- 다만 Redisson을 쓰더라도 분산락이 rollback이나 정합성을 자동 보장하는 것은 아니므로, DB transaction, unique key, 멱등성 설계는 별도로 필요합니다.

꼬리 질문으로는 이런 것들이 나올 수 있습니다.

- Redisson lock watchdog은 어떤 문제를 해결하나요?
- Redisson의 pub/sub 기반 대기는 spin lock과 어떻게 다른가요?
- Redisson을 쓰면 Lua script 기반 unlock을 직접 구현하지 않아도 되는 이유는 무엇인가요?
- Redisson도 Redis 장애 상황에서는 어떤 한계를 가지나요?
- 단순 Redis cache 용도라면 Redisson보다 Lettuce가 더 적합할 수 있는 이유는 무엇인가요?

---

## 답변

> **한 줄 핵심**: Lettuce는 "명령을 다루는 범용 클라이언트", Redisson은 "Redis 위에 분산 동기화 도구를 얹은 라이브러리" — 분산락처럼 **정확히 구현하기 어려운 것**이 필요할 때, 직접 구현(260714의 함정 전부)을 검증된 구현으로 대체하는 것이 선택 이유다. 단, 분산 시스템의 본질적 한계까지 없애 주지는 않는다.

### 1문 1답

**Q. Lettuce보다 Redisson을 선택할 수 있는 이유는 무엇인가요?**

**A.** 두 라이브러리는 추상화 수준이 다른데, Lettuce는 netty 기반 범용 Redis 클라이언트(Spring Boot 기본)로 명령을 직접 다루기 좋지만, 분산락을 만들려면 SET NX PX 원자 획득·소유자 UUID 검증·Lua 안전 해제·TTL 연장·대기와 재시도를 전부 직접 구현하고 그 엣지 케이스를 스스로 책임져야 한다. Redisson은 그 각각을 내장으로 제공한다 — RLock이라는 java.util.concurrent.locks.Lock 계열 인터페이스, Lua로 원자 처리되는 획득·해제와 소유자 검증, lease 미지정 시 TTL을 자동 연장하는 watchdog, 스핀 폴링 없이 해제 알림을 받는 pub/sub 대기, 재진입, 그리고 공정 락·ReadWriteLock·Semaphore 같은 상위 도구까지. 요약하면 "직접 만들면 틀리기 쉬운 부분이 검증된 구현으로 제공된다"가 선택 이유다. 다만 두 선은 그어야 한다 — Redisson을 써도 락은 상호배제 도구일 뿐이라 rollback·정합성은 DB 트랜잭션·unique 제약·멱등성으로 따로 설계해야 하고, Redis 장애나 failover 시의 분산 시스템 본질 한계도 그대로 남는다.

**Q. Lettuce는 어떤 클라이언트이고, 락을 직접 구현하면 무엇을 신경 써야 하나요?**

**A.** Lettuce는 netty 기반의 범용 Redis 클라이언트로, Spring Boot의 기본 클라이언트이며 명령을 직접 다루기에 좋습니다. SET NX PX 같은 명령으로 분산락을 직접 구현할 수는 있습니다. 다만 그러려면 SET NX PX 원자 획득, 소유자 UUID 검증, Lua 기반 안전 해제, TTL 연장, 대기와 재시도 전략을 전부 직접 구현해야 합니다. 게다가 그 각각의 엣지 케이스까지 스스로 책임져야 합니다. 즉 Lettuce는 저수준 도구를 주지만, 분산락의 정확성은 온전히 구현자의 몫으로 남습니다.

**Q. Redisson은 Lettuce 대비 무엇을 제공해서 락을 단순하고 안정적으로 만드나요?**

**A.** Redisson은 RLock이라는 java.util.concurrent.locks.Lock 계열의 익숙한 인터페이스를 제공해 락 사용 코드를 단순하게 만듭니다. 내부적으로는 Lua로 원자 처리되는 획득·해제와 소유자 검증, lease를 지정하지 않으면 TTL을 자동 연장하는 watchdog, 스핀 폴링 없이 해제 알림을 받는 pub/sub 대기, 재진입 지원을 내장합니다. 여기에 공정 락, ReadWriteLock, Semaphore, CountDownLatch 같은 상위 동기화 도구까지 제공합니다. 이들은 260714에서 직접 구현이 감당해야 했던 함정 목록과 1:1로 대응됩니다 — SETNX+EXPIRE 분리 문제는 원자 획득 내장으로, GET-후-DEL 레이스는 Lua compare-and-delete 내장으로 대체됩니다. 요약하면 "직접 만들면 틀리기 쉬운 부분이 검증된 구현으로 제공된다"가 선택 이유입니다.

**Q. Redisson을 써도 별도로 설계해야 하는 것은 무엇인가요?**

**A.** 락은 어디까지나 상호배제 도구일 뿐이라, rollback이나 정합성을 자동으로 보장하지 않습니다. 그래서 DB 트랜잭션, unique 제약, 멱등성 설계는 락과 별도로 마련해야 합니다. 또한 Redisson도 분산 시스템의 본질적 한계는 없애지 못합니다 — TTL 만료 경계의 늦은 쓰기(GC pause), master 장애 시 비동기 복제로 인한 락 유실, Redis 다운 시 락 기능 전체 불능이 그것입니다. 이는 라이브러리 품질 문제가 아니라 아키텍처의 성질이라, 데이터 레벨 방어(unique·조건부 UPDATE·멱등성)가 여전히 필요합니다. 즉 Redisson은 구현 실수는 없애 주지만, 설계 책임까지 없애 주지는 않습니다.

**Q. Redisson lock watchdog은 어떤 문제를 해결하나요?**

**A.** 고정 TTL은 딜레마를 안고 있습니다 — 짧으면 작업 도중 만료되어 동시 진입이 생기고, 넉넉히 길게 잡으면 홀더가 죽었을 때 그 시간 내내 모든 요청이 막힙니다. 문제의 뿌리는 작업 시간은 변동하는데 TTL은 획득 시점에 고정해야 한다는 정보 비대칭입니다. watchdog은 스레드가 살아있는 동안 TTL을 주기적으로 갱신해서, 이 lease 추정 자체를 불필요하게 만듭니다. 그 결과 작업이 얼마나 길어지든 도중 만료가 없고, JVM이 죽으면 갱신이 멈춰 자동 해제됩니다. 대신 hang 상태에서도 계속 연장된다는 부작용이 있어, 상세는 260716에서 다룹니다.

**Q. Redisson의 pub/sub 기반 대기는 spin lock과 어떻게 다른가요?**

**A.** spin은 대기자가 능동적으로 주기적으로 재시도(폴링)하는 방식이고, pub/sub은 해제 알림을 받고 그때만 재시도하는 이벤트 기반 방식입니다. spin은 대기자 수 × 폴링 빈도만큼 Redis에 부하가 계속 가해지고, "해제~다음 폴링" 사이의 인계 지연도 생깁니다. 반면 pub/sub은 유휴 대기 중에는 요청이 없고 해제 즉시 반응합니다. 이는 OS 동시성에서의 spin lock vs 조건변수(wait/notify) 구도가 분산 환경에 그대로 재현된 것입니다. 그래서 경합이 심할수록 pub/sub의 이점이 커집니다(상세는 260717).

**Q. Redisson을 쓰면 Lua script 기반 unlock을 직접 구현하지 않아도 되는 이유는 무엇인가요?**

**A.** unlock()이 이미 그 Lua를 내장하고 있기 때문입니다. 구체적으로는 "소유자(클라이언트ID:스레드ID) 확인 → 재진입 카운트 감소 → 0이면 삭제 → 대기자에게 해제 알림 publish"가 스크립트 하나로 원자 실행됩니다. 그래서 직접 구현 시 생기는 GET-후-DEL 레이스(260714)가 라이브러리 레벨에서 이미 제거돼 있습니다. 또한 소유자가 아닌 스레드가 unlock을 호출하면 IllegalMonitorStateException으로 차단됩니다. 즉 안전한 해제에 필요한 원자성과 소유자 검증이 기본 제공되므로 직접 짤 필요가 없습니다.

**Q. Redisson도 Redis 장애 상황에서는 어떤 한계를 가지나요?**

**A.** 크게 세 가지입니다. 첫째, Redis가 죽으면 락 기능 전체가 불능이 되는 가용성 결합이 있습니다. 둘째, master가 죽고 락 key가 replica로 복제되기 전에 failover되면, 새 master에서 다른 클라이언트가 같은 락을 잡을 수 있습니다 — 비동기 복제의 한계입니다. 셋째, GC pause나 네트워크 단절로 인한 TTL 만료 경계 문제도 그대로 남습니다. 정리하면 Redisson은 "구현 실수"는 없애 주지만 "분산 시스템의 본질적 한계"는 없애 주지 못하므로, fail-open/fail-closed 정책과 데이터 레벨 방어가 여전히 설계 대상입니다.

**Q. 단순 Redis cache 용도라면 Redisson보다 Lettuce가 더 적합할 수 있는 이유는 무엇인가요?**

**A.** Lettuce는 Spring Boot의 spring-data-redis 기본 클라이언트라 추가 의존성이 필요 없습니다. 그리고 캐시 용도에는 Redisson이 제공하는 가치, 즉 분산 동기화 도구가 쓰일 일이 없습니다. 쓰지도 않을 추상화 계층을 들여오면 의존성, 직렬화(codec) 차이, 학습 비용만 추가됩니다. 원칙은 "필요한 추상화 수준에 맞는 도구"를 쓰는 것으로, 캐시는 저수준 클라이언트로 충분합니다. 실제로는 한 프로젝트에서 캐시는 Lettuce, 락은 Redisson으로 공존시키는 구성도 흔합니다.

### 면접 답변 (구술용)

두 라이브러리는 추상화 수준이 다릅니다. Lettuce는 netty 기반의 범용 Redis 클라이언트로 Spring Boot의 기본 클라이언트이고, 명령을 직접 다루기에 좋습니다. 문제는 분산락을 만들려면 SET NX PX 원자 획득, 소유자 UUID 검증, Lua 기반 안전 해제, TTL 연장, 대기와 재시도 전략을 전부 직접 구현하고 그 엣지 케이스를 스스로 책임져야 한다는 겁니다. Redisson은 그 각각을 내장으로 제공합니다 — RLock이라는 java.util.concurrent.locks.Lock 계열의 익숙한 인터페이스, Lua로 원자 처리되는 획득·해제와 소유자 검증, lease를 지정하지 않으면 TTL을 자동 연장해 주는 watchdog, 스핀 폴링 없이 해제 알림을 받는 pub/sub 대기, 재진입 지원, 그리고 공정 락·ReadWriteLock·Semaphore 같은 상위 동기화 도구까지. 요약하면 "직접 만들면 틀리기 쉬운 부분이 검증된 구현으로 제공된다"가 선택 이유입니다. 다만 두 가지 선은 그어야 합니다 — Redisson을 써도 락은 상호배제 도구일 뿐이라 rollback이나 정합성은 DB 트랜잭션·unique 제약·멱등성으로 따로 설계해야 하고, Redis 장애나 failover 시의 분산 시스템 본질 한계도 그대로 남습니다.

### 원리 이해 (왜 그런가)

**추상화 수준 비교:**

| | Lettuce | Redisson |
|---|---|---|
| 정체 | 범용 Redis 클라이언트 (netty, 비동기) | Redis 기반 분산 객체·동기화 라이브러리 |
| 락 구현 | SET NX PX + Lua + 재시도 전부 직접 | RLock에 내장 |
| 대기 | 재시도 루프 직접 (스핀 위험) | pub/sub 알림 대기 (→ 260717) |
| TTL 관리 | 고정 TTL, 연장 직접 | watchdog 자동 연장 (→ 260716) |
| 재진입 | 불가 | 스레드별 카운트로 지원 |
| 상위 도구 | — | FairLock, ReadWriteLock, Semaphore, CountDownLatch |
| 적정 용도 | 캐시·일반 명령 (Boot 기본) | 분산 동기화가 필요할 때 |

**Redisson이 "구현 실수"를 없애는 지점** — 260714의 함정 목록과 1:1 대응됩니다: SETNX+EXPIRE 분리 문제 → 원자 획득 내장, GET-후-DEL 레이스 → Lua compare-and-delete 내장, TTL 추정 실패 → watchdog, 스핀 폴링 → pub/sub 대기.

**Redisson이 못 없애는 것 (분산 시스템의 본질)** — TTL 만료 경계의 늦은 쓰기(GC pause), master 장애 시 비동기 복제로 인한 락 유실, Redis 다운 시 락 기능 전체 불능. 이건 라이브러리 품질 문제가 아니라 아키텍처의 성질이라, 데이터 레벨 방어(unique·조건부 UPDATE·멱등성)가 여전히 필요합니다.

### 꼬리질문 Q&A

**Q. Redisson lock watchdog은 어떤 문제를 해결하나요?**

**A.** **"lease time을 미리 정확히 못 박아야 하는" 추정 문제를 해결한다.**
작업 시간은 변동하는데 고정 TTL은 짧으면 도중 만료, 길면 장애 시 장기 잠금이라는 딜레마가 있습니다. watchdog은 스레드가 살아있는 동안 TTL을 주기 갱신해 이 추정 자체를 불필요하게 만듭니다. 대신 hang 상태에서도 연장된다는 부작용이 있어서, 상세는 260716에서 다룹니다.

**Q. Redisson의 pub/sub 기반 대기는 spin lock과 어떻게 다른가요?**

**A.** **spin은 대기자가 능동적으로 주기 재시도(폴링), pub/sub은 해제 알림을 받고 그때만 재시도(이벤트 기반).**
spin은 대기자 수 × 폴링 빈도만큼 Redis에 부하가 계속 가해지고 "해제~다음 폴링" 사이의 인계 지연도 있습니다. pub/sub은 유휴 대기 중 요청이 없고 해제 즉시 반응합니다 — OS 동시성의 spin lock vs 조건변수(wait/notify) 구도가 분산 환경에 재현된 것입니다(→ 260717).

**Q. Redisson을 쓰면 Lua 기반 unlock을 직접 구현하지 않아도 되는 이유는?**

**A.** **unlock()이 이미 그 Lua를 내장하고 있기 때문이다 — "소유자(클라이언트ID:스레드ID) 확인 → 재진입 카운트 감소 → 0이면 삭제 → 대기자에게 해제 알림 publish"가 스크립트 하나로 원자 실행된다.**
직접 구현 시 생기는 GET-후-DEL 레이스(260714)가 라이브러리 레벨에서 이미 제거돼 있고, 소유자가 아닌 스레드가 unlock하면 IllegalMonitorStateException으로 차단됩니다.

**Q. Redisson도 Redis 장애 상황에서는 어떤 한계를 가지나요?**

**A.** **① Redis가 죽으면 락 기능 전체가 불능(가용성 결합), ② master가 죽고 락 key가 replica로 복제되기 전에 failover되면 새 master에서 다른 클라이언트가 같은 락을 잡을 수 있음(비동기 복제의 한계), ③ GC pause·네트워크 단절로 인한 TTL 만료 경계 문제도 그대로.**
정리하면 Redisson은 "구현 실수"는 없애 주지만 "분산 시스템의 본질적 한계"는 없애 주지 못합니다. 그래서 fail-open/fail-closed 정책(260711)과 데이터 레벨 방어가 여전히 설계 대상입니다.

**Q. 단순 Redis cache 용도라면 Lettuce가 더 적합할 수 있는 이유는?**

**A.** **Boot의 spring-data-redis 기본 클라이언트라 추가 의존성이 없고, 캐시에는 Redisson의 가치(분산 동기화 도구)가 쓰일 일이 없기 때문이다.**
쓰지 않을 추상화 계층을 들여오면 의존성·직렬화(codec) 차이·학습 비용만 추가됩니다. 원칙은 "필요한 추상화 수준에 맞는 도구" — 캐시는 저수준 클라이언트로 충분하고, 분산 동기화가 필요해지는 시점에 Redisson을 더하면 됩니다(둘은 한 프로젝트에서 공존 가능합니다 — 캐시는 Lettuce, 락은 Redisson).

### 🌱 심화 키워드
- **RLock / java.util.concurrent.locks.Lock** — 로컬 락 인터페이스의 분산 확장이라는 설계
- **codec (직렬화)** — Redisson 도입 시 기존 데이터와의 호환에서 자주 걸리는 지점
- **RReadWriteLock / RSemaphore / RCountDownLatch** — 분산 환경으로 확장된 동시성 도구 세트
- **비동기 복제와 failover 유실** — Redis 기반 락의 아키텍처적 한계
- **fail-open / fail-closed** — Redis 장애 시의 정책 축 (→ 260711)

### 🔗 참고 자료
- Redisson 공식 문서/위키 — "Distributed locks and synchronizers" (RLock, watchdog, fair lock)
- Spring Boot 공식 문서 — Data Redis (기본 클라이언트가 Lettuce라는 사실 확인)

### ❓ 더 파볼 질문
**Q. Redisson은 pub/sub 대기용 연결을 어떻게 관리하나?**

**A.** 구독 전용 커넥션(풀)을 일반 명령 커넥션과 분리해서 관리한다. 락을 대량으로 쓰면 구독 채널·커넥션 수가 늘어나므로, 커넥션 설정(subscription pool 크기)이 운영 튜닝 지점이 된다 — "락도 커넥션을 먹는다"는 사실을 잊기 쉽다.

**Q. spring-data-redis와 Redisson은 어떻게 같이 쓰나?**

**A.** redisson-spring-data 모듈이 RedisConnectionFactory 구현을 제공해 스프링 캐시 추상화(@Cacheable)까지 Redisson으로 태울 수도 있고, 반대로 캐시는 Lettuce로 두고 RedissonClient는 락 전용 빈으로만 추가하는 구성도 흔하다. 후자가 변경 범위가 작아 도입이 쉽다.

**Q. RedissonFairLock(공정 락)은 내부적으로 무엇이 더 필요한가?**

**A.** 대기자 순서를 기록하는 큐(list)와 대기자별 타임아웃 관리가 추가된다 — 그래서 일반 락보다 Redis 연산이 많고 느리다. "순서 보장"이 비즈니스 요구일 때만 쓰고, 아니면 일반 락 + 재시도가 낫다는 트레이드오프의 근거다(구현 세부는 버전에 따라 다를 수 있음 — 개요 수준으로 이해).
