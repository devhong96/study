# 260702 Dispatchers.IO에서 동시에 실행되는 coroutine 수가 많아지면 thread pool 고갈을 어떻게 방지할 수 있을까요?

Dispatchers.IO에서 동시에 실행되는 coroutine 수가 많아지면 thread pool 고갈을 어떻게 방지할 수 있을까요?

Kotlin Coroutine을 사용해본 분들이라면 Dispatchers.IO를 자연스럽게 쓰는 경우가 많습니다.
그런데 면접에서는 “비동기니까 괜찮다”에서 끝나지 않고, 동시에 너무 많은 작업이 몰렸을 때 어떤 문제가 생기는지 물어볼 수 있습니다.

이 질문은 단순히 coroutine 문법을 아는지보다,
비동기 작업도 결국 CPU, Thread, DB Connection, 외부 API 처리량 같은 제한된 자원을 사용한다는 걸 이해하고 있는지 확인하는 질문에 가깝습니다.

같이 체크해보면 좋은 포인트는 아래와 같습니다.

- Dispatchers.IO는 blocking I/O 작업을 처리하기 위한 dispatcher
- coroutine은 가볍지만, blocking 작업이 많아지면 실제 thread 사용량이 증가할 수 있음
- DB Connection Pool, 외부 API rate limit보다 많은 동시 작업을 만들면 병목이 생김
- Semaphore, bounded queue, rate limit 등으로 동시 실행 개수를 제한할 수 있음
- 작업 성격별로 별도 dispatcher/thread pool을 분리하는 것도 고려 가능

꼬리질문으로는 이런 질문이 이어질 수 있습니다.

- Coroutine은 가벼운데 왜 thread pool 고갈 문제가 생길 수 있나요?
- Dispatchers.IO와 Dispatchers.Default는 어떤 차이가 있나요?
- DB 작업을 coroutine으로 많이 날리면 어떤 문제가 생길 수 있나요?
- Coroutine에서 backpressure는 어떻게 구현할 수 있을까요?
- 외부 API 호출을 coroutine으로 병렬 처리할 때 동시성 제한은 어떻게 둘 수 있나요?

---

## 답변

> **한 줄 핵심**: coroutine이 가벼운 건 suspend일 때뿐이고, Dispatchers.IO 위의 blocking 작업은 "coroutine 1개 = 스레드 1개 점유"다 — 그래서 답은 스레드 숫자 조정이 아니라 **동시성 총량을 하위 자원(DB 풀, rate limit) 용량에 맞춰 제한**하는 것이다.

### 1문 1답

**Q. Dispatchers.IO에서 동시에 실행되는 coroutine 수가 많아지면 thread pool 고갈을 어떻게 방지할 수 있을까요?**

**A.** 전제부터 바로잡으면, coroutine이 가벼운 건 suspend 지점에서 스레드를 놓기 때문인데 Dispatchers.IO에서 하는 일은 대부분 JDBC 같은 blocking I/O라 스레드를 쥔 채 기다린다 — 이 영역에선 coroutine 1개가 실제 스레드 1개를 점유해 가벼움이 성립하지 않는다. Dispatchers.IO의 기본 상한은 64와 코어 수 중 큰 값인데, 사실 그 상한이 차기 전에 DB 커넥션 풀이나 외부 API가 먼저 무너지는 경우가 보통이다. 방지책은 네 가지다 — 첫째, Semaphore나 limitedParallelism으로 동시 실행 개수를 제한하되 그 숫자를 스레드가 아니라 하위 자원 용량(커넥션 풀 크기, 상대 API rate limit)에 맞춘다. 둘째, 작업 성격별로 dispatcher를 분리해 한쪽 폭주가 다른 쪽을 굶기지 않게 격리한다. 셋째, 무제한 launch 대신 Channel 기반 worker나 Flow의 flatMapMerge로 유입 자체를 처리 속도에 맞춰 제어한다. 넷째, 근본적으로 R2DBC나 suspend 클라이언트 같은 non-blocking으로 바꾸면 스레드 점유 문제 자체가 사라지지만, 그래도 하위 자원 한계는 남아 동시성 제한은 여전히 필요하다.

**Q. Dispatchers.IO는 어떤 작업을 위한 dispatcher인가요?**

**A.** Dispatchers.IO는 JDBC 호출처럼 스레드를 쥔 채 결과를 기다리는 blocking I/O 작업을 처리하기 위한 dispatcher입니다. 이런 대기 중인 스레드는 실제로 CPU를 쓰지 않고 잠들어 있기 때문에, 코어 수보다 스레드가 많아도 손해가 아닙니다. 그래서 IO의 기본 상한은 64와 코어 수 중 큰 값으로, CPU 바운드용인 Default(≈코어 수)보다 넉넉하게 잡혀 있습니다. 다만 이 상한은 "무한"이 아니므로 blocking coroutine을 수백 개 띄우면 결국 이 상한에 걸립니다. 사실 그전에 DB 커넥션 풀이나 외부 API 같은 하위 자원이 먼저 무너지는 경우가 대부분입니다.

**Q. Semaphore, bounded queue, rate limit 등으로 동시 실행 개수를 어떻게 제한하나요?**

**A.** 동시에 실행되는 개수는 Semaphore(n).withPermit이나 Dispatchers.IO.limitedParallelism(n) 같은 도구로 제한할 수 있습니다. 여기서 핵심은 제한값 n을 스레드 숫자가 아니라 커넥션 풀 크기나 상대 API의 rate limit 같은 "가장 좁은 하위 자원"의 용량에 맞추는 것입니다. 예를 들어 커넥션이 10개인데 스레드를 64개 풀어주면 54개는 커넥션을 기다리며 타임아웃 위험만 키우기 때문입니다. limitedParallelism은 IO의 64개를 쪼개 갖는 게 아니라 독립적인 병렬도 예산을 새로 만들어 준다는 점도 알아두면 좋습니다. 또 유입 자체는 용량 제한 Channel이나 flatMapMerge(concurrency=n)로 조절해, 제한 지점 앞에 대기 코루틴이 무한히 쌓여 메모리를 압박하는 것을 막습니다.

**Q. 작업 성격별로 dispatcher/thread pool을 분리하면 어떤 이점이 있나요?**

**A.** 작업 성격별로 DB용 dispatcher와 외부 API용 dispatcher를 따로 두면, 한쪽이 폭주하거나 느려져도 다른 쪽이 스레드를 뺏겨 굶는 일을 막을 수 있습니다. 예컨대 외부 API 응답이 지연되어 그쪽 스레드가 다 잠기더라도, DB 작업은 자기 전용 dispatcher에서 영향 없이 계속 돌아갑니다. 이렇게 자원을 칸막이로 나눠 장애를 국소화하는 것이 bulkhead(격벽) 패턴이며, 이는 전통적인 스레드 풀 분리와 정확히 같은 사상입니다. 한 자원의 문제가 시스템 전체로 번지지 않게 격리한다는 점에서 안정성 설계의 기본기입니다.

**Q. Coroutine은 가벼운데 왜 thread pool 고갈 문제가 생길 수 있나요?**

**A.** coroutine이 가볍다는 명제는 코드가 suspend일 때만 참입니다. suspend 함수는 대기 지점에서 스레드를 반납하므로 스레드 하나가 수천 개의 코루틴을 번갈아 실행할 수 있습니다. 그런데 Dispatchers.IO에서 하는 일은 대부분 JDBC 같은 blocking 호출이라, suspend가 아니라 스레드를 쥔 채 잠듭니다. 이 영역에서는 coroutine 1개가 실제 스레드 1개를 점유하므로, 동시에 실행되는 blocking 작업의 수가 곧 필요한 실제 스레드 수가 됩니다. 그래서 coroutine을 아무리 많이 만들어도 동시성은 스레드 상한(기본 64)에서 멈추고, 그 지점이 병목이 됩니다.

**Q. Dispatchers.IO와 Dispatchers.Default는 어떤 차이가 있나요?**

**A.** 두 dispatcher는 용도와 상한 정책이 다릅니다. Default는 CPU 바운드 작업용이라 상한이 대략 코어 수인데, CPU 작업은 코어보다 스레드가 많아봤자 컨텍스트 스위칭 낭비만 생기기 때문입니다. 반대로 IO는 blocking 대기용이고, 대기 중인 스레드는 CPU를 쓰지 않으므로 코어 수보다 많아도 되어 기본 max(64, 코어 수)로 잡습니다. 흥미로운 점은 이 둘이 하나의 공유 스레드 풀 위에 얹힌 뷰라는 것입니다. 그래서 withContext로 Default와 IO 사이를 전환해도 실제 스레드 이동은 일어나지 않는다는 특성이 kotlinx.coroutines 문서에 명시돼 있습니다.

**Q. DB 작업을 coroutine으로 많이 날리면 어떤 문제가 생길 수 있나요?**

**A.** DB 작업을 coroutine으로 대량으로 날리면, 스레드(기본 64)보다 커넥션 풀(예: HikariCP 10)이 먼저 고갈됩니다. 스레드 64개가 확보돼도 그중 DB 작업들은 커넥션 10개를 두고 경쟁하기 때문에 진짜 병목은 보통 커넥션 쪽입니다. 초과 요청은 커넥션 대기 큐에 쌓이다가 connection timeout 예외로 터지고, DB 입장에서도 동시 세션이 폭증하면 내부 경합만 커집니다. 그래서 처방은 동시성 제한을 커넥션 풀 크기에 정렬하고, 풀 크기는 다시 DB의 실제 처리 능력에 정렬하는 것입니다. 결국 제한 기준을 "가장 좁은 자원"으로 통일하는 것이 핵심입니다.

**Q. Coroutine에서 backpressure는 어떻게 구현할 수 있을까요?**

**A.** 코루틴에서는 suspend 자체가 가장 자연스러운 backpressure 수단입니다. 용량이 제한된 Channel은 가득 차면 send가 suspend되어 생산자가 저절로 느려지고, Flow는 기본이 pull 기반이라 소비자 속도에 맞춰 상류가 진행됩니다. 세부 조절이 필요하면 buffer로 용량을 지정하거나, conflate로 중간값을 건너뛰거나, collectLatest로 새 값이 오면 이전 처리를 취소하는 식으로 상황에 맞춰 씁니다. 이 방식의 특징은 초과분을 거부(rejection)하는 것이 아니라 "생산자를 재우는" 것이라, 데이터 유실 없이 속도를 맞출 수 있다는 점입니다. 이것이 초과 작업을 버리거나 예외를 던지는 스레드 풀의 RejectedExecutionHandler와 근본적으로 다른 지점입니다.

**Q. 외부 API 호출을 coroutine으로 병렬 처리할 때 동시성 제한은 어떻게 둘 수 있나요?**

**A.** 외부 API 병렬 호출에서는 Semaphore로 "동시 개수"를, rate limiter로 "초당 개수"를 제한하는데, 이 둘은 서로 다른 별개의 제약입니다. 예를 들어 Semaphore(20)으로 동시에 도는 호출을 20개로 묶었다고 해도, 각 호출이 10ms에 끝난다면 초당 2,000건이 나갈 수 있습니다. 즉 동시성을 제한한다고 해서 초당 요청 수가 자동으로 제한되는 것은 아닙니다. 그래서 상대 API의 제한이 RPS(초당 요청 수) 기준이라면, 동시성 제한과 별도로 토큰 버킷류의 rate limiter를 반드시 병행해야 합니다. 두 제약을 혼동하면 동시성은 지켰는데도 상대 API의 rate limit에 걸리는 상황이 생깁니다.

### 면접 답변 (구술용)

전제부터 바로잡아야 하는데, coroutine이 가벼운 이유는 suspend 지점에서 스레드를 놓기 때문입니다. 그런데 Dispatchers.IO에서 하는 일은 대부분 JDBC 같은 blocking I/O라서 suspend가 아니라 스레드를 쥔 채 기다립니다 — 이 영역에서는 coroutine 1개가 실제 스레드 1개를 점유하므로 가벼움이 성립하지 않습니다. Dispatchers.IO의 기본 상한은 64와 코어 수 중 큰 값인데, blocking coroutine을 수백 개 띄우면 그 상한이 차고, 사실 그 전에 DB 커넥션 풀이나 외부 API가 먼저 무너지는 경우가 보통입니다. 방지 전략은 네 가지입니다. 첫째, Semaphore나 limitedParallelism으로 동시 실행 개수를 제한하되 그 숫자를 스레드가 아니라 하위 자원 용량 — 커넥션 풀 크기, 상대 API의 rate limit — 에 맞춥니다. 둘째, 작업 성격별로 dispatcher를 분리해서 한쪽 폭주가 다른 쪽을 굶기지 않게 격리합니다. 셋째, 유입 자체를 제어합니다 — 무제한 launch 대신 Channel 기반 worker나 Flow의 flatMapMerge로 처리 속도에 맞춰 유입이 자연히 멈추게 합니다. 넷째, 근본적으로는 R2DBC나 suspend 클라이언트 같은 non-blocking으로 바꾸면 스레드 점유 문제 자체가 사라집니다. 다만 그래도 하위 자원 한계는 남으니 동시성 제한은 여전히 필요합니다.

### 원리 이해 (왜 그런가)

**"가벼움"의 조건:**

```
suspend 호출:  대기 시점에 스레드 반납 → 스레드 1개가 코루틴 수천 개를 번갈아 실행 (가벼움 성립)
blocking 호출: 스레드를 쥔 채 잠듦     → 동시 실행 수 = 필요한 실제 스레드 수 (가벼움 붕괴)
```

**병목의 실제 순서** — 스레드보다 하위 자원이 먼저 무너진다:

```
coroutine 500개 동시 launch
  → Dispatchers.IO 스레드 64개 점유, 436개 대기        (스레드 병목)
  → 그 64개 중 DB 작업들은 커넥션 10개를 두고 경쟁      (진짜 병목은 보통 여기)
  → 커넥션 대기 타임아웃 예외, 응답 지연 전파
```
제한값 n을 스레드가 아니라 "가장 좁은 자원"에 맞춰야 하는 이유입니다 — 커넥션이 10개면 스레드 64개를 풀어줘도 54개는 커넥션 대기만 하며 타임아웃 위험만 키웁니다.

**방지 전략 4가지:**

| 전략 | 도구 | 근거 |
|------|------|------|
| 동시 실행 제한 | `Semaphore(n).withPermit { }`, `Dispatchers.IO.limitedParallelism(n)` | n = 하위 자원 용량. limitedParallelism은 IO의 64개를 나눠 갖는 게 아니라 독립 병렬도 예산을 만든다 |
| 격리(bulkhead) | DB용/외부 API용 dispatcher 분리 | 외부 API 지연으로 스레드가 잠겨도 DB 작업은 영향 없음 |
| 유입 제어(backpressure) | 용량 제한 Channel + 고정 worker, `flatMapMerge(concurrency = n)` | 무제한 launch는 제한 지점 앞에 대기 코루틴을 무한히 쌓음(메모리 압박) |
| blocking 제거 | Ktor client, WebClient, R2DBC | 대기 중 스레드 미점유 → 문제 범주 자체가 소멸 (단, 하위 자원 제한은 여전히 필요) |

### 꼬리질문 Q&A

**Q. Coroutine은 가벼운데 왜 thread pool 고갈이 생기나요?**

**A.** **가벼움의 조건이 suspend이기 때문이다.**
suspend 함수는 대기 시점에 스레드를 반납하지만, blocking 호출은 스레드를 쥔 채 잠듭니다. 그래서 blocking 작업의 동시 실행 수는 곧 필요한 실제 스레드 수가 되고, coroutine을 아무리 많이 만들어도 동시성은 스레드 상한(기본 64)에서 멈춥니다. "coroutine이 가볍다"는 명제는 코드가 진짜 suspend일 때만 참입니다.

**Q. Dispatchers.IO와 Dispatchers.Default의 차이는?**

**A.** **용도와 상한 정책이 다르다 — Default는 CPU 바운드용(≈코어 수), IO는 blocking 대기용(기본 max(64, 코어 수)).**
근거: CPU 작업은 코어보다 많은 스레드가 있어봤자 스위칭 낭비지만, 대기 중인 스레드는 CPU를 안 쓰므로 코어보다 많아도 됩니다. 그리고 두 dispatcher는 하나의 공유 스레드 풀 위의 뷰라서, Default↔IO 간 withContext 전환 시 실제 스레드 이동이 일어나지 않는다는 것도 kotlinx.coroutines 문서에 명시된 특성입니다.

**Q. DB 작업을 coroutine으로 대량으로 날리면 어떤 문제가 생기나요?**

**A.** **스레드(64)보다 커넥션 풀(예: HikariCP 10)이 먼저 고갈된다.**
초과 요청은 커넥션 대기 큐에 쌓이다 connection timeout 예외가 터지고, DB 입장에서도 동시 세션 폭증은 내부 경합만 키웁니다. 처방은 동시성 제한을 커넥션 풀 크기에 정렬하고, 풀 크기는 DB의 실제 처리 능력에 정렬하는 것 — 제한을 "가장 좁은 자원" 기준으로 통일하는 겁니다.

**Q. Coroutine에서 backpressure는 어떻게 구현하나요?**

**A.** **suspend 자체가 자연스러운 backpressure 수단이다.**
용량 제한 Channel은 가득 차면 send가 suspend되어 생산자가 저절로 느려지고, Flow는 기본이 pull 기반이라 소비자 속도에 맞춰 상류가 진행됩니다. 조절 연산자로 `buffer`(용량 지정), `conflate`(중간값 스킵), `collectLatest`(신규 도착 시 이전 처리 취소)를 상황에 맞게 씁니다. 거부(rejection)가 아니라 "생산자를 재우는" 방식이라 데이터 유실 없이 속도를 맞출 수 있다는 게 스레드 풀의 RejectedExecutionHandler와의 차이입니다.

**Q. 외부 API 병렬 호출의 동시성 제한은 어떻게 두나요?**

**A.** **Semaphore로 동시 개수를, rate limiter로 초당 개수를 제한한다 — 둘은 별개의 제약이다.**
```kotlin
val sem = Semaphore(20)
val results = items.map { async { sem.withPermit { api.call(it) } } }.awaitAll()
```
동시성 20이어도 각 호출이 10ms면 초당 2,000건이 나갑니다. 상대 API 제한이 RPS 기준이면 토큰 버킷류 rate limiter를 병행해야 합니다.

### 🌱 심화 키워드
- **limitedParallelism** — dispatcher 뷰에 독립 병렬도 예산을 부여하는 API
- **structured concurrency** — 부모-자식 스코프로 취소·에러가 전파되는 코루틴의 뼈대
- **Channel / Flow(buffer, conflate)** — 코루틴 세계의 backpressure 도구들
- **bulkhead** — 자원 격리 패턴 (스레드 풀 분리와 동일 사상, → 260707)
- **runBlocking** — 서버 코드에서 피해야 할 블로킹 브리지

### 🔗 참고 자료
- kotlinx.coroutines 공식 문서 — Dispatchers.IO(기본 64 상한, Default와의 스레드 공유), limitedParallelism
- Kotlin 공식 가이드 — "Coroutine context and dispatchers", "Asynchronous Flow"

### ❓ 더 파볼 질문
- **Virtual Thread(Loom) 시대에 Dispatchers.IO의 의미는 어떻게 달라지나?**
  ↳ blocking 호출을 VT에 태우면 "blocking = 스레드 점유"라는 전제가 깨지므로 IO 디스패처의 존재 이유가 약해진다. JDK 21+에서는 VT 기반 executor를 디스패처로 감싸 blocking 작업을 처리하는 조합이 가능하고, 코루틴과 VT의 역할 정리는 아직 진행 중인 주제다 — "경량 동시성 두 모델의 공존"이라는 관점으로 지켜볼 부분.
- **runBlocking을 서버 코드에서 피해야 하는 이유는?**
  ↳ 호출 스레드를 통째로 블로킹해서 코루틴의 장점을 소거하고, 톰캣 요청 스레드에서 쓰면 스레드 점유가 이중이 된다. 특히 병렬도가 제한된 디스패처 안에서 runBlocking으로 같은 디스패처의 작업을 기다리면 스레드가 서로를 기다리는 데드락도 가능하다.
- **flatMapMerge(concurrency)는 내부적으로 어떻게 동시 수를 제한하나?**
  ↳ 내부적으로 채널 기반으로 upstream 값을 받아 concurrency 개수만큼만 내부 Flow를 동시에 collect하는 구조다. 초과분은 자연히 suspend 대기하므로, "동시 n개 + 나머지는 대기"가 연산자 하나로 표현된다.
