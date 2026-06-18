# Spring: @Async / @EventListener / @TransactionalEventListener 정리

> 관련 문서: [../internals/sync-async-blocking-nonblocking.md](../internals/sync-async-blocking-nonblocking.md) — 동기/비동기·블로킹/논블로킹 4조합 (이벤트는 결합도 축, @Async가 스레드 축)

## 0. 한 줄 결론

`@Async`와 이벤트 리스너는 **비교 대상이 아니다.** 서로 다른 축(axis)의 개념이며 조합해서 쓴다.

| 개념 | 다루는 문제 | 한 줄 정의 |
|------|------------|-----------|
| `@Async` | **스레드** (어디서 실행되나) | "이 메서드를 호출자와 다른 스레드에서 실행해라" |
| `@EventListener` | **결합도** (누가 호출하나) | "이 사건이 발생하면 알려줘 (발행자는 나를 몰라도 됨)" |
| `@TransactionalEventListener` | **부수효과 시점** (언제 실행되나) | "롤백 불가능한 부수효과를 커밋 결과에 동기화해라" |

---

## 1. @EventListener는 기본이 동기(synchronous)다 ← 가장 큰 오해

"이벤트 = 비동기"는 착각이다.

```java
@Transactional
public void placeOrder(Order order) {
    orderRepository.save(order);
    publisher.publishEvent(new OrderPlacedEvent(order));  // (A)
    log.info("발행 완료");                                  // (B)
}

@EventListener
public void onOrder(OrderPlacedEvent e) {
    // (A)에서 즉시, 같은 스레드, 같은 트랜잭션에서 실행됨
    // 이 리스너가 끝나야 (B)가 실행됨
}
```

- `publishEvent()`는 **메서드 직접 호출과 실행 흐름이 동일**하다.
- 리스너가 끝날 때까지 발행자는 블로킹되고, 리스너 예외는 발행자까지 전파된다.
- 유일한 차이는 **컴파일 타임 결합 제거** (발행자가 리스너의 존재를 모름).

### 이벤트 리스너의 진짜 가치

단순히 "서비스 클래스가 커지는 걸 막는" 수준이 아니라 **확장점(extension point)** 이다.
발행자 코드를 건드리지 않고 리스너를 계속 추가할 수 있다(개방-폐쇄 원칙).

> 참고: DB 작업 한정으로는 일반 `@EventListener`(동기)가 같은 트랜잭션에 참여하므로
> 컨슈머 실패 시 발행자까지 롤백된다 → **완전한 원자성**을 덤으로 얻는다.

---

## 2. @Async — 실행 스레드 분리

별도 스레드에서 돌리고 싶으면 `@Async`를 붙인다. 리스너든 일반 메서드든 무관.

```java
@Async                          // @EnableAsync 필요
@EventListener
public void onOrder(OrderPlacedEvent e) {
    // 별도 스레드풀에서 실행
    // 발행자는 publishEvent() 직후 바로 다음 줄로 진행
    // 발행자 트랜잭션과 분리됨, 예외도 발행자에게 전파 안 됨
}
```

### 조합 매트릭스

| | 동기 | 비동기 |
|--|------|--------|
| **직접 호출** | 그냥 메서드 호출 | `@Async` 메서드 호출 |
| **이벤트** | `@EventListener` | `@Async` + `@EventListener` |

`@Async`는 세로축, 이벤트는 가로축. 직교한다.

### 스레드를 분리해서 얻는 이점

1. **응답 지연시간 단축** — 발행자 스레드가 느린 작업을 안 기다리고 즉시 반환 (fire-and-forget).
2. **요청 처리 스레드 풀 보호 (격리 / bulkhead)** — 가장 중요.
   - `@Async`는 스레드를 *아끼는* 게 아니라 *다른 풀로 옮기는* 것이다.
   - 느린 작업이 폭주해도 그 영향이 Async 풀 안에 갇힌다 → 톰캣 풀은 멀쩡 → 빠른 요청은 계속 처리.
3. **병렬 처리로 총 소요시간 단축** — 독립 작업 N개를 동시에: 총시간 = 합(sum)이 아니라 최댓값(max).
   ```java
   CompletableFuture<A> a = apiService.callA();   // @Async
   CompletableFuture<B> b = apiService.callB();
   CompletableFuture<C> c = apiService.callC();
   CompletableFuture.allOf(a, b, c).join();       // 600ms → 약 200ms
   ```
4. **부하 평탄화 (backpressure)** — 유한 풀 + 큐 구조라 순간 폭주를 완충.

### @Async 주의 — 만능 아님

- **CPU 바운드 작업은 효과 거의 없음.** 일을 옮길 뿐 줄이지 않는다. 이득은 **I/O 대기**가 있을 때.
- **결과가 필요하면 이득 반감.** `Future.get()`으로 블로킹하면 스레드를 다시 잡는다 (단, 여러 개 던지고 한 번에 join은 OK).
- **풀을 반드시 bounded로.** 기본 `SimpleAsyncTaskExecutor`는 무제한 → OOM 위험.
  `ThreadPoolTaskExecutor`로 코어/맥스/큐/거부정책을 명시할 것.
- **컨텍스트가 전파 안 됨.** 트랜잭션, `SecurityContext`, 요청 스코프 빈, MDC 로깅 모두 새 스레드에 자동 전파 안 됨.
- **예외가 삼켜짐.** `void` 반환 시 `AsyncUncaughtExceptionHandler` 등록 권장.

> 순수 I/O 바운드 fire-and-forget이면 Java 21 가상 스레드(Spring Boot 3.2+ `spring.threads.virtual.enabled`)가
> 더 단순할 수 있다. 단, 풀 격리·큐 기반 백프레셔처럼 "제어"가 필요하면 여전히 `@Async` + bounded 풀이 유효.

---

## 3. @TransactionalEventListener — 부수효과를 커밋 결과에 동기화

### 일반 @EventListener의 문제

`@EventListener`는 **트랜잭션 커밋 전에** 실행된다.

```java
@Transactional
public void placeOrder(Order order) {
    orderRepository.save(order);
    publisher.publishEvent(new OrderPlacedEvent(order));  // 리스너가 여기서 실행
    paymentClient.charge(order);   // ← 여기서 예외 → 트랜잭션 전체 롤백!
}

@EventListener
public void sendEmail(OrderPlacedEvent e) {
    emailClient.send("주문 완료!");  // 이미 메일 발송됨. 근데 주문은 롤백되어 DB에 없음.
}
```

### 해결 — 트랜잭션 phase에 바인딩

```java
@TransactionalEventListener   // 기본 phase = AFTER_COMMIT
public void sendEmail(OrderPlacedEvent e) {
    emailClient.send("주문 완료!");  // 커밋 성공해야만 실행, 롤백되면 호출 안 됨
}
```

### phase 종류

| phase | 실행 시점 |
|-------|----------|
| `BEFORE_COMMIT` | 커밋 직전 |
| `AFTER_COMMIT` **(기본값)** | 커밋 성공 후 |
| `AFTER_ROLLBACK` | 롤백 후 |
| `AFTER_COMPLETION` | 커밋이든 롤백이든 끝난 후 |

- `fallbackExecution` 기본값 `false` → **활성 트랜잭션이 없으면 리스너가 조용히 무시됨** (디버깅 함정).

### 일반 @EventListener vs @TransactionalEventListener (AFTER_COMMIT)

| | 일반 `@EventListener` | `@TransactionalEventListener` (AFTER_COMMIT) |
|--|--|--|
| 트랜잭션 | 발행자와 **같은** 트랜잭션 | 발행자 트랜잭션 **밖**, 커밋 후 |
| 컨슈머 실패 시 | 발행자까지 롤백 (완전 원자성) | 발행자는 **이미 커밋됨, 롤백 불가** |
| 적합한 작업 | 롤백 **가능한** 작업 (DB) | 롤백 **불가능한** 작업 (메일, MQ, 외부 API) |

---

## 4. 핵심 함정 두 가지

### ① AFTER_COMMIT은 비동기가 아니다

`AFTER_COMMIT` 리스너도 **발행자와 같은 스레드**에서 실행된다.
"커밋 후"일 뿐 "다른 스레드"가 아니다. 비동기로 만들려면 `@Async`를 추가해야 한다.

```java
@Async                        // 이게 있어야 진짜 비동기
@TransactionalEventListener   // 커밋 후
public void sendEmail(OrderPlacedEvent e) { ... }
```

### ② AFTER_COMMIT에서 DB를 또 건드리려면 새 트랜잭션이 필요

커밋 후 시점이라 원래 트랜잭션은 이미 끝났다. 새 트랜잭션을 열어야 한다.

```java
@TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
@Transactional(propagation = Propagation.REQUIRES_NEW)  // 새 트랜잭션 필수
public void writeAuditLog(OrderPlacedEvent e) {
    auditRepository.save(...);
}
```

---

## 5. @TransactionalEventListener는 "정합성 보장"이 아니다

`@TransactionalEventListener(AFTER_COMMIT)`는 **단방향 보장**이다.

- 발행자 롤백 → 컨슈머 실행 안 함 ✅ (orphan side effect 방지: 데이터 없는데 부수효과 발생하는 것 방지)
- 발행자 커밋 → 컨슈머 실행... 그런데 **컨슈머가 실패하면?** ❌ 발행자는 이미 커밋됨 (lost side effect: 데이터는 있는데 부수효과 누락)

따라서 정확한 표현은 "정합성 보장"이 아니라 **"부수효과의 실행 시점을 트랜잭션 결과에 동기화"** 다.

### 어떤 작업에 써야 하나 — 축이 두 개다

| 축 | 메일 발송 | 결제 |
|--|--|--|
| **되돌릴 수 있나?** | ❌ 불가능 (보낸 메일 회수 불가) | ✅ 가능 (환불·취소·void) |
| **실패해도 되나?** | ✅ 괜찮음 (주문은 유효, 재발송) | ❌ 안 됨 (실패하면 주문 자체가 무효) |

판단 기준은 *"롤백 불가능한가"* 가 아니라 **"실패해도 원본 데이터가 유효한가(best-effort인가)"** 다.

- ✅ **AFTER_COMMIT 리스너 적합 (best-effort):**
  알림 메일/푸시, 검색 인덱스 갱신, 캐시 무효화, 분석/통계 이벤트 발행, 감사 로그 외부 전송, 환영 메일.
- ❌ **부적합 (must-succeed):**
  결제처럼 실패하면 원본 데이터가 무효가 되는 작업. → Saga 패턴 / 보상 거래(authorize-capture)의 영역.

양방향 정합성(데이터와 부수효과가 무조건 함께)이 필요하면 어노테이션 레벨이 아니라
**Transactional Outbox 패턴**으로 가야 한다.

---

## 6. 최종 의사결정 가이드

```
다른 컴포넌트와 결합을 끊고 싶다          → 이벤트 사용
  ├─ DB 커밋과 무관하게 즉시 처리         → @EventListener
  └─ DB가 확정된 뒤에만 처리해야 한다     → @TransactionalEventListener (AFTER_COMMIT)

발행자를 블로킹하지 않고 별도 스레드로    → 위 어디에든 @Async 추가
```

**전형적인 실무 패턴** (커밋 확정 + 발행자 논블로킹 + 메일 등 외부 호출):

```java
@Async
@TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
public void sendEmail(OrderPlacedEvent e) { ... }
```

---

## 7. 공통 주의사항

- `@Async`와 `@Transactional` 모두 **프록시 기반** → 같은 클래스 내부 호출(self-invocation)에서는 동작 안 함.
- `@Async`는 `@EnableAsync` 필요. `@TransactionalEventListener`는 별도 활성화 어노테이션 불필요(자동).
- `@Async` void 메서드의 예외는 호출자에게 전파되지 않음 → `AsyncUncaughtExceptionHandler`로 로깅.
