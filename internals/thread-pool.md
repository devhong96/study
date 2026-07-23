# 스레드 풀 (Thread Pool)

스프링 애플리케이션에서 비동기 작업이 늘어나 스레드 풀이 꽉 차거나 넘어가면 어떻게 되는가?
→ **어떤 `ThreadPoolExecutor` 설정을 썼느냐**에 따라 동작이 완전히 달라진다.

> 관련 문서:
> - [process-thread-memory.md](./process-thread-memory.md) - 프로세스/스레드 메모리 구조와 가상 메모리
> - [multicore-memory.md](./multicore-memory.md) - 멀티코어 환경에서 스레드 풀과 캐시 일관성
> - [context-switching.md](./context-switching.md) - 스레드 과다 시 컨텍스트 스위칭 누적 비용 (자발/비자발 CS, 최적 풀 크기)

---

## 1. 스레드 풀의 핵심 파라미터

```java
new ThreadPoolExecutor(
    corePoolSize,      // 기본 유지 스레드 수
    maximumPoolSize,   // 최대 스레드 수
    keepAliveTime,     // 초과 스레드 유지 시간
    workQueue,         // 작업 대기 큐
    rejectedHandler    // 거부 정책
);
```

| 파라미터 | 설명 |
|---------|------|
| `corePoolSize` | 평소 유지되는 기본 스레드 수 |
| `maximumPoolSize` | 만들 수 있는 최대 스레드 수 |
| `keepAliveTime` | core 초과 스레드가 idle 상태일 때 유지 시간 |
| `workQueue` | 처리 대기 중인 Task 를 담는 큐 |
| `rejectedHandler` | 큐도 차고 max 도 넘었을 때 어떻게 할지 |

---

## 2. 스레드 풀이 작업을 받았을 때의 흐름

```
요청 들어옴
    ↓
[1] core 스레드 비어있나? → YES → 새 스레드 만들어서 실행
    ↓ NO
[2] Queue 에 자리 있나?   → YES → Queue 에 대기
    ↓ NO (Queue 가득)
[3] max 까지 여유 있나?   → YES → 새 스레드 만들어서 실행 (core 초과)
    ↓ NO (max 도달)
[4] RejectedExecutionHandler 발동 ← 여기가 "넘쳤다"
```

> 핵심 포인트: **Queue 가 먼저 채워지고, 그 다음에 max 까지 스레드가 늘어난다.**
> 그래서 큐 사이즈가 무제한이면 max 까지 도달하지도 못한 채 큐만 계속 쌓인다.

---

## 3. 큐가 꽉 차고 max 도 넘으면? → 거부 정책 4가지

`RejectedExecutionHandler` 가 결정한다.

### 3-1. `AbortPolicy` (기본값)

```java
executor.setRejectedExecutionHandler(new ThreadPoolExecutor.AbortPolicy());
```

**동작**: `RejectedExecutionException` 을 던진다.

```java
try {
    executor.execute(task);
} catch (RejectedExecutionException e) {
    // 호출자가 직접 처리해야 함
    log.error("작업 거부됨", e);
}
```

**언제 쓰나**
- **실패를 명확하게 알아야 할 때** (결제, 주문 같은 중요 작업)
- 호출자가 재시도 로직을 갖고 있을 때
- 모니터링/알람을 걸어둬야 할 때

**주의**: 예외 처리 안 하면 호출 흐름이 통째로 깨진다. `@Async` 메서드 안에서 발생하면 잡기도 까다로움.

---

### 3-2. `CallerRunsPolicy` ⭐ 실무 권장

```java
executor.setRejectedExecutionHandler(new ThreadPoolExecutor.CallerRunsPolicy());
```

**동작**: 풀이 꽉 차면 **호출한 스레드가 직접 `task.run()` 을 실행**한다.

```
[Tomcat 워커] → executor.execute(task)
                       ↓ (풀 가득)
                       ↓ CallerRunsPolicy 발동
[Tomcat 워커가 직접 task 실행] ← 워커가 묶임
                       ↓
새 HTTP 요청 처리 속도 ↓ → 자연스러운 backpressure
```

**언제 쓰나**
- 작업을 **버리면 안 되는 경우** (로그, 이벤트 발행 등)
- 트래픽 폭주 시 자연스럽게 속도 조절하고 싶을 때
- 시스템 안정성이 처리량보다 중요할 때

**주의**: 호출자가 Tomcat 워커면 그 워커가 묶이는 동안 다른 HTTP 요청을 못 받음. 처리량이 급감할 수 있다.

---

### 3-3. `DiscardPolicy` ⚠️ 위험

```java
executor.setRejectedExecutionHandler(new ThreadPoolExecutor.DiscardPolicy());
```

**동작**: **아무것도 안 함**. 작업을 조용히 버린다. 예외도, 로그도 없다.

```java
public void rejectedExecution(Runnable r, ThreadPoolExecutor e) {
    // 비어있음
}
```

**언제 쓰나**
- **버려도 진짜 상관없는 작업** (예: 통계용 비핵심 로그)
- 거의 안 쓴다.

**주의**: 디버깅 지옥. "왜 처리가 안 되지?" 추적이 거의 불가능. 쓰려면 최소한 wrapping 해서 로그라도 남겨야 한다.

```java
executor.setRejectedExecutionHandler((r, e) -> {
    log.warn("작업 버려짐: queue={}, active={}", e.getQueue().size(), e.getActiveCount());
});
```

---

### 3-4. `DiscardOldestPolicy`

```java
executor.setRejectedExecutionHandler(new ThreadPoolExecutor.DiscardOldestPolicy());
```

**동작**: 큐의 **가장 오래된 작업을 버리고**, 새 작업을 큐에 넣는다.

```
큐: [T1, T2, T3, T4, T5] (가득)
       ↓ 새 작업 T6 도착
큐: [T2, T3, T4, T5, T6]  ← T1 버려짐
```

**언제 쓰나**
- **최신 데이터가 더 중요한 경우** (실시간 가격, 센서 값, 최신 알림)
- 오래된 작업은 이미 의미가 없어졌을 때

**주의**:
- 오래 기다린 작업이 손해를 봄 (공정성 X)
- `PriorityBlockingQueue` 와 같이 쓰면 우선순위 높은 게 버려질 수 있어서 위험

---

### 3-5. 한눈에 비교

| 정책 | 작업 손실 | 예외 | Backpressure | 실무 사용도 |
|------|----------|------|--------------|------------|
| AbortPolicy | X (예외 던짐) | O | X | 중간 |
| **CallerRunsPolicy** | X (호출자가 처리) | X | **O** | **높음** |
| DiscardPolicy | O (조용히 버림) | X | X | 낮음 |
| DiscardOldestPolicy | O (오래된 것) | X | X | 특수 상황 |

### 3-6. 선택 가이드

```
작업을 버려도 되는가?
├─ NO → 빠른 실패가 필요한가?
│       ├─ YES → AbortPolicy (재시도 로직 필수)
│       └─ NO  → CallerRunsPolicy ⭐
│
└─ YES → 어떤 걸 버릴까?
         ├─ 최신이 중요 → DiscardOldestPolicy
         └─ 아무거나 OK → DiscardPolicy (로그라도 남기자)
```

---

## 4. 스프링에서 실제로 어떻게 되는가

### 4-1. `@Async` 의 기본 동작 (함정 주의)

스프링 부트의 기본 `TaskExecutor` 설정:

```java
corePoolSize  = 8                  // CPU 코어 수 기반
maxPoolSize   = Integer.MAX_VALUE
queueCapacity = Integer.MAX_VALUE  // ← 무제한 큐!
```

**무제한 큐**라서 사실상 max 스레드까지 안 가고 **큐에 계속 쌓인다**.
→ 메모리 터질 때까지 **OOM (OutOfMemoryError)** 발생.

### 4-2. Tomcat 워커 스레드 풀

HTTP 요청 처리용 스레드 풀이 `@Async` 와 별도로 존재한다.

```yaml
server:
  tomcat:
    threads:
      max: 200              # 최대 워커
      min-spare: 10
    accept-count: 100       # OS 레벨 대기 큐 크기
    max-connections: 8192
```

- max(200) + queue(100) 까지 차면 → **새 요청은 connection refused** 또는 **타임아웃**
- 클라이언트는 503 / 504 응답을 받음

---

## 5. 실무에서 자주 마주치는 증상

| 증상 | 원인 |
|------|------|
| 응답 지연 폭증 | 큐에 쌓이면서 latency 누적 |
| OOM | 무제한 큐에 Task 객체가 쌓여서 힙 고갈 |
| `RejectedExecutionException` | 거부 정책이 AbortPolicy 일 때 |
| Connection refused | Tomcat 레벨에서 막힘 |
| 호출 스레드 블로킹 | CallerRunsPolicy 로 요청 스레드가 직접 처리 → 처리량 급감 |

---

## 6. 권장 설정 패턴

```java
@Bean
public TaskExecutor taskExecutor() {
    ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
    executor.setCorePoolSize(10);
    executor.setMaxPoolSize(50);
    executor.setQueueCapacity(100);          // ← 반드시 제한!
    executor.setRejectedExecutionHandler(
        new ThreadPoolExecutor.CallerRunsPolicy()  // backpressure
    );
    executor.setThreadNamePrefix("async-");
    executor.initialize();
    return executor;
}
```

### 왜 `CallerRunsPolicy` 를 많이 쓰는가?

거부하지 않고 **호출자가 직접 처리**하게 해서 **자연스러운 backpressure** 가 걸린다.
요청을 받는 쪽이 느려지니까 상류에서 알아서 속도를 줄이게 됨.

```
[클라이언트] → [Tomcat 워커] → @Async 호출
                    ↓ (풀이 가득 참)
                    ↓ CallerRunsPolicy 발동
                    ↓ Tomcat 워커가 직접 작업 실행
                    ↓ → 워커가 묶이니까 새 HTTP 요청 처리 속도가 자연스럽게 떨어짐
                    ↓ → 클라이언트 입장에서 느려지므로 트래픽 감소 효과
```

---

## 7. 핵심 요약

> **큐 크기를 반드시 제한하고, 거부 정책을 명시적으로 정해라.**
> 안 그러면 OOM 으로 죽거나, 응답 지연이 무한정 늘어난다.

### 체크리스트
- [ ] `queueCapacity` 를 명시적으로 설정했는가? (기본 무제한은 위험)
- [ ] `RejectedExecutionHandler` 를 명시했는가?
- [ ] Tomcat 워커 풀과 `@Async` 풀을 분리해서 모니터링하는가?
- [ ] 스레드 풀 메트릭 (active count, queue size) 을 노출하고 있는가?

---

## 8. 가상 메모리와의 관계

> 관련 문서: [process-thread-memory.md](./process-thread-memory.md)

스레드 풀의 모든 설정은 결국 **"공유 가상 주소 공간을 어떻게 나눠 쓸 것인가"** 의 문제로 환원된다.

### 8-1. 스레드 하나 = 가상 메모리에 새 Stack 영역 할당

스레드를 만들면 가장 큰 비용은 **Stack 메모리**. 그리고 그 Stack 은 **프로세스의 가상 주소 공간 안에 새 영역으로 할당**된다.

```
프로세스 가상 주소 공간 (64bit JVM)

기존 영역 (공유)
┌─────────────────────────────────────┐
│ Text │ Data │ BSS │     Heap        │ ← 변하지 않음
└─────────────────────────────────────┘

풀이 스레드를 만들 때마다 ↓
┌────────┐ ┌────────┐ ┌────────┐ ... ┌────────┐
│Stack T1│ │Stack T2│ │Stack T3│     │Stack T200│
│ ~1MB   │ │ ~1MB   │ │ ~1MB   │     │  ~1MB    │
└────────┘ └────────┘ └────────┘     └────────┘
```

- JVM 기본 Stack: `-Xss` 보통 **512KB ~ 1MB**
- 1000 스레드 → Stack 만으로 약 **1GB 가상 주소** 소비
- 32bit JVM 은 가상 주소 자체가 2~4GB 한계 → 스레드 수 상한
- 64bit JVM 은 가상 주소 한계는 풀리지만 **물리 RAM** 이 새 제약

### 8-2. 스레드 풀이 존재하는 이유 (가상 메모리 관점)

스레드 생성/소멸 시 OS 가 하는 일.

```
스레드 생성:
[1] 가상 주소 공간에 Stack 영역 확보
[2] 페이지 테이블 엔트리 생성
[3] TLS 영역 할당
[4] OS thread descriptor 등록
[5] 스케줄러에 등록

스레드 소멸:
[1] 위 자원 모두 해제
[2] TLB 무효화
```

매번 이걸 하면 비싸니까 풀이 재사용. 게다가 **Demand Paging** 때문에:
- 새 스레드 Stack 페이지는 처음엔 RAM 에 없음
- 첫 함수 호출 시 **Minor Page Fault** 발생
- 풀에서 재사용하면 이 fault 가 없음 → **응답 latency 안정**

### 8-3. 풀 사이즈와 메모리 충돌

#### 풀이 너무 크면 → 가상 메모리 / RAM 압박
```java
executor.setMaxPoolSize(5000);  // 위험
```
- Stack 가상 주소: 5000 × 1MB = **5GB**
- Heap 경쟁: 5000 스레드 동시 할당 → GC pause 폭증
- TLB pressure 증가
- 컨텍스트 스위칭 누적 비용

#### 큐가 무제한이면 → Heap 폭발
```java
queueCapacity = Integer.MAX_VALUE
```
```
요청 폭주 → 큐에 Task 객체 무한 적재
       ↓ (모두 Heap 에 할당, Heap 은 공유 영역)
Heap 가상 주소 사용량 ↑
       ↓
물리 RAM 부족 → Major Page Fault 폭증
       ↓
Thrashing → OOM
```

→ **큐 크기 제한**이 가상 메모리 관점에서도 정당화됨.

### 8-4. Heap 공유와 race condition

가상 주소 공간에서 **Heap 은 모든 스레드가 공유**. 풀 안 스레드들이 같은 객체를 동시에 건드릴 수 있음.

```java
@Service
public class CounterService {
    private int count = 0;  // Heap → 모든 스레드 공유

    @Async
    public void increment() {
        count++;  // race condition
    }
}
```

반면 **Stack 의 지역변수**는 스레드별 독립이라 안전.

```java
@Async
public void process() {
    int localVar = 0;   // Stack → 안전
    localVar++;
}
```

스레드 풀 = 같은 가상 주소 공간을 공유하는 N 개 실행 흐름. 풀 사이즈 늘리면 동시성 버그가 더 잘 드러난다.

### 8-5. `ThreadLocal` 과 TLS

스레드별 독립 영역 = **TLS (Thread Local Storage)**. `ThreadLocal` 이 자바 구현.

```java
private static final ThreadLocal<UserContext> ctx = new ThreadLocal<>();
```

#### 스레드 풀에서 위험한 이유
```
[풀에서 스레드 T1 빌려옴]
     ↓
ctx.set(userA);   // TLS 에 저장
     ↓
[작업 완료, T1 풀로 반환]
     ↓  ← ctx.remove() 안 함
[다른 요청이 T1 빌려옴]
     ↓
ctx.get();        // userA 데이터 남아있음 (보안 사고)
```

- TLS 데이터는 스레드가 살아있는 한 가상 주소 공간 점유
- 풀의 스레드는 안 죽으므로 → **TLS 메모리 누수**
- 누적되면 Heap 사용량 ↑ → GC pressure ↑

```java
try {
    ctx.set(value);
    // 작업
} finally {
    ctx.remove();  // 필수
}
```

### 8-6. 실무 메모리 계산 예시

```yaml
server.tomcat.threads.max: 200

JVM:
  -Xss512k
  -Xmx4g

@Async 풀 maxPoolSize: 50
스케줄러 풀: 10
```

| 영역 | 사용량 |
|------|--------|
| Heap | 4 GB |
| Metaspace | ~300 MB |
| Tomcat 워커 Stack | 200 × 512KB = 100 MB |
| @Async Stack | 50 × 1MB = 50 MB |
| 스케줄러 Stack | 10 × 1MB = 10 MB |
| Direct Buffer, JIT 코드 캐시 등 | ~500 MB |
| **합계 (가상)** | **~5 GB** |

→ **컨테이너 메모리 limit 을 Heap (`-Xmx`) 만 보고 설정하면 OOM Killer 에 죽는다.** Stack/Metaspace/Native 영역까지 합산 필수.

### 8-7. 핵심 연결고리 한눈에

| 스레드 풀 개념 | 가상 메모리 연결 |
|---------------|-----------------|
| 스레드 생성 비용 | Stack 가상 주소 할당 + 페이지 테이블 갱신 |
| 스레드 재사용 (풀) | Stack 재사용 → Minor Page Fault 회피 |
| 풀 사이즈 제한 | 가상 주소 + 물리 RAM 한계 반영 |
| 큐 크기 제한 | Heap 무한 증가 방지 (OOM 회피) |
| `CallerRunsPolicy` | Heap 폭발 전 backpressure |
| Heap 공유 | 같은 가상 주소 공간 → race condition |
| Stack 독립 | 스레드별 별도 가상 영역 → 지역변수 안전 |
| `ThreadLocal` | TLS = 스레드별 독립 가상 메모리 |
| 컨텍스트 스위칭 | 같은 페이지 테이블 → TLB flush 없음 |
| `-Xss` 튜닝 | Stack 당 가상 주소 사용량 조절 |

### 8-8. 종합 튜닝 가이드

```java
// 1. 풀 사이즈 = Stack × 개수 고려
executor.setCorePoolSize(Runtime.getRuntime().availableProcessors() * 2);
executor.setMaxPoolSize(Runtime.getRuntime().availableProcessors() * 4);

// 2. 큐는 반드시 제한 (Heap 보호)
executor.setQueueCapacity(500);

// 3. 거부 정책 → backpressure
executor.setRejectedExecutionHandler(
    new ThreadPoolExecutor.CallerRunsPolicy()
);

// 4. ThreadLocal cleanup
try {
    contextHolder.set(value);
} finally {
    contextHolder.remove();
}
```

```bash
# JVM 옵션
-Xss256k                  # Stack 작게 → 더 많은 스레드 가능
-Xmx4g                    # Heap 명시
-XX:+AlwaysPreTouch       # 시작 시 페이지 미리 RAM 에 → 런타임 Major Fault 감소
```

### 한 줄 요약

> **스레드 풀의 모든 설정은 결국 "공유 가상 주소 공간을 어떻게 효율적으로/안전하게 나눠 쓸 것인가" 의 문제다.**
> Heap 은 공유라서 race condition / OOM 위험, Stack 은 스레드마다 가상 주소 영역을 따로 먹으니 풀 크기에 비례해 메모리 사용량 증가.

---

## ❓ 남은 질문

1. `queueCapacity` 를 0(`SynchronousQueue`)으로 두면 흐름이 어떻게 달라지나?

   → **답:** 큐에 쌓지 않고 곧바로 스레드에 넘기려 시도하며, 여유 스레드가 없으면 max 까지 즉시 스레드를 늘리고 그마저 차면 바로 거부한다. `Executors.newCachedThreadPool` 이 이 방식이다.
2. `CallerRunsPolicy` 인데 풀(executor)이 이미 `shutdown` 된 상태에서 작업이 거부되면?

   → **답:** 호출 스레드에서 실행하지 않고 그 작업을 조용히 버린다. shutdown 중 backpressure 를 기대하다 유실이 생기는 함정이다.
3. 스프링 `@Async` 메서드가 `void` 를 반환할 때 내부에서 던진 예외는 어디로 가나?

   → **답:** 호출자에게 전파되지 않고 `AsyncUncaughtExceptionHandler` 로 넘어간다(미설정 시 로그만 남음). `Future`/`CompletableFuture` 반환이면 `get()` 호출 시점에 전파된다.
