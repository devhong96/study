# 260721 : Backpressure를 적용하지 않으면 어떤 장애가 발생할 수 있나요?

Backpressure를 적용하지 않으면 어떤 장애가 발생할 수 있나요?

이 질문은 트래픽이 몰릴 때 서버가 요청을 "그냥 다 받는 구조"인지, 아니면 처리 가능한 만큼만 받아서 시스템을 보호하는 구조인지 확인하기 좋은 질문입니다.

같이 체크해보면 좋은 포인트는 아래와 같습니다.

- Backpressure는 생산 속도가 소비 속도보다 빠를 때, 요청량이나 데이터 흐름을 제어하는 방식이다.
- 적용하지 않으면 처리하지 못한 요청이 계속 queue나 memory에 쌓일 수 있다.
- 그 결과 memory 사용량 증가, thread pool 고갈, latency 증가, timeout 증가, OOM 같은 장애로 이어질 수 있다.
- 특히 외부 API 호출, 메시지 처리, WebFlux stream, 대량 이벤트 처리처럼 생산자와 소비자의 속도 차이가 큰 구조에서 문제가 커진다.
- 따라서 queue 크기 제한, timeout, rate limit, drop/retry 정책, circuit breaker 등을 함께 설계해 시스템이 감당 가능한 범위 안에서 동작하게 해야 한다.

---

## 답변

> **한 줄 핵심**: Backpressure의 부재는 곧 **"흐름 제어가 없는 큐"**다 — 도착률(λ)이 처리율(μ)을 넘는 순간 큐가 무한히 자라고, 그 여파가 메모리(OOM) → 스레드/커넥션 고갈 → latency·timeout 폭증 → 재시도 폭풍 → **연쇄 장애(cascading failure)**로 층층이 번진다. 핵심은 "요청을 다 받는가"가 아니라 **"감당 못 할 부하를 소비자가 생산자에게 되돌려 알릴 수단이 있는가"**다.

### 1문 1답

**Q. Backpressure를 적용하지 않으면 어떤 장애가 발생할 수 있나요?**

**A.** 근본 원인은 큐잉 이론 한 줄로 정리된다 — 도착률 λ가 처리율 μ보다 크면 큐 길이는 시간에 비례해 무한히 자란다(안정 조건 λ<μ가 깨짐). Backpressure가 없다는 건 이 λ를 소비자 능력에 맞춰 줄일 피드백이 없다는 뜻이라, 넘치는 요청이 큐·버퍼·메모리에 계속 적재된다. 그 결과가 순차적으로 터진다. ① 무한 버퍼면 힙이 차서 **OOM**, ② 요청마다 스레드/커넥션을 물고 대기하면 **thread pool·DB connection pool 고갈**, ③ 큐가 깊어질수록 대기시간이 늘어 **latency·timeout 증가**, ④ timeout난 클라이언트가 재시도하면 λ가 더 커지는 **retry storm(재시도 폭풍)**, ⑤ 한 서비스의 포화가 상류 호출자의 스레드까지 묶어 **연쇄 장애**로 번진다. 즉 단일 장애가 아니라 **되먹임으로 증폭되는 장애 연쇄**가 본질이다.

**Q. Backpressure는 정확히 무엇을 하는 메커니즘인가요?**

**A.** 소비자가 "지금 n개까지만 감당 가능하다"는 **수요(demand) 신호를 생산자에게 거꾸로 보내** 생산 속도를 소비 속도에 묶는 흐름 제어다. Reactive Streams 규격이 이를 `Subscription.request(n)`으로 표준화했는데, Publisher는 Subscriber가 요청한 만큼만 emit한다 — 수요가 충분하면 push처럼, 소비자가 느리면 pull처럼 동작하는 **push-pull 하이브리드**다(흔히 "dynamic push-pull"로 부른다 — 정확한 문구가 규격 원문에 그대로 있는지는 확인 필요). 네트워크 계층에도 이미 같은 원리가 있다: TCP는 수신 버퍼가 차면 window 크기를 줄여(끝까지 차면 zero window) 송신자를 늦춘다(TCP flow control). Backpressure는 이 "받는 쪽이 보내는 쪽을 늦추는 신호"를 애플리케이션 계층까지 끌어올린 것이다.

**Q. 왜 latency가 늘어나는 것이 timeout·재시도로 이어지나요?**

**A.** Little's Law(L = λ·W)의 직관으로 보면, 처리율이 고정인데 큐에 쌓인 항목 수 L이 커질수록 각 요청의 체류시간 W가 비례해 늘어난다(엄밀히는 안정 상태 관계지만, "큐가 깊을수록 오래 기다린다"는 방향은 그대로 성립). 뒤에 들어온 요청은 "이미 클라이언트가 포기한(timeout) 뒤에야" 처리되기 시작한다 — **아무도 안 기다리는 응답을 만드느라 자원을 태우는** 상태다. 포기한 클라이언트가 재시도하면 λ가 더 커지고, 이게 μ를 더 밀어내는 양의 되먹임이 된다. 그래서 backpressure(입구 제어)와 함께 **deadline/timeout으로 오래된 요청을 버리는 정책**이 짝을 이뤄야 한다.

**Q. 어떤 구조에서 이 문제가 특히 커지나요?**

**A.** **생산자와 소비자의 속도 차가 크고, 그 사이 버퍼가 있는 모든 경계**에서 커진다. 외부 API 호출(상대가 느리면 내 스레드가 묶임), 메시지 컨슈머(Kafka는 프로듀서를 못 늦추니 컨슈머가 poll 속도로 스스로 제어), WebFlux 스트림(빠른 소스 + 느린 sink), 대량 이벤트·센서 데이터처럼 **소스를 늦출 수 없는 경우**가 대표적이다. 특히 소스를 늦출 수 없는 구조에서는 backpressure 신호를 위로 못 보내므로, buffer·drop·sampling 같은 **감쇠 전략**으로 대신 감당해야 한다.

### 면접 답변 (구술용)

Backpressure는 생산 속도가 소비 속도보다 빠를 때, 소비자가 "여기까지만 받을 수 있다"는 신호를 생산자에게 되돌려 흐름을 제어하는 방식입니다. 이걸 적용하지 않으면 처리 못 한 요청이 큐나 버퍼, 메모리에 계속 쌓이는데, 근본적으로는 도착률이 처리율을 넘는 순간 큐가 무한히 자라는 문제입니다. 그 결과가 층층이 터집니다 — 무한 버퍼면 메모리 사용량이 늘어 OOM, 요청마다 스레드나 커넥션을 물고 있으면 thread pool과 DB connection pool 고갈, 큐가 깊어지면 latency와 timeout 증가, 그리고 timeout난 클라이언트가 재시도하면 부하가 더 커지는 재시도 폭풍, 마지막으로 상류 서비스까지 묶이는 연쇄 장애로 번집니다. 특히 외부 API 호출이나 메시지 처리, WebFlux 스트림처럼 생산자와 소비자 속도 차가 큰 구조에서 문제가 심해집니다. 그래서 실무에서는 backpressure 하나만이 아니라 큐 크기 제한, timeout, rate limit, drop/retry 정책, circuit breaker를 함께 설계해서 시스템이 감당 가능한 범위 안에서만 동작하도록 합니다. 요청을 "다 받는" 게 아니라 "받을 수 있는 만큼만 받고 나머지는 빠르게 거절하는" 게 오히려 시스템을 지키는 방향입니다.

### 원리 이해 (왜 그런가)

**장애 연쇄 4→5단계 (되먹임으로 증폭):**

| 단계 | 무슨 일 | 근본 원인 | 방치 시 |
|------|---------|-----------|---------|
| ① 적재 | 큐·버퍼·메모리에 미처리 요청 누적 | λ > μ → 큐 길이 무한 증가 | 힙 고갈 → **OOM** / GC 폭주 |
| ② 자원 고갈 | 요청이 스레드·커넥션을 물고 대기 | 대기 요청 수만큼 자원 점유 | **thread pool / DB pool 고갈** → 신규 요청 거절조차 못 함 |
| ③ 지연 | 체류시간 W 증가 | Little's Law L=λW, L↑ | **latency·timeout 증가** |
| ④ 증폭 | 포기한 클라이언트가 재시도 | timeout → retry → λ 추가 상승 | **retry storm** (양의 되먹임) |
| ⑤ 전파 | 상류 호출자 스레드까지 블로킹 | 동기 호출 체인의 자원 결합 | **cascading failure** |

**왜 "무한히" 자라는가**: 큐는 λ<μ일 때만 안정(정상상태에서 길이 유한)하다. λ≥μ면 들어오는 속도가 빠지는 속도를 넘어 큐 길이가 발산한다. Backpressure는 λ를 μ 이하로 되돌리는 **피드백 루프**다 — 이게 없으면 유한 버퍼는 overflow, 무한 버퍼는 OOM, 둘 중 하나로 귀결된다.

**Reactive Streams 수요 신호 (push-pull 하이브리드):**
```
Publisher                         Subscriber
   │  onSubscribe(subscription)  →  │
   │  ← request(n)  (n개만 줘)       │   // 소비자가 수요 선언
   │  onNext × n                  → │
   │  ← request(m)  (더 줘)          │   // 처리한 만큼 다시 요청
```
소비자가 `request(n)`으로 허락한 만큼만 흐른다. 소비자가 느리면 request가 늦게 와서 생산자가 자연히 멈춘다 — 버퍼 없이도 속도가 맞춰지는 이유. (규격 핵심 인터페이스는 Publisher·Subscriber·Subscription·Processor 4개.)

**Reactor 오버플로 전략 (소스를 못 늦출 때의 대안):**

| 전략 | 동작 | 언제 |
|------|------|------|
| `onBackpressureBuffer` | 넘치면 버퍼(무제한/상한+콜백) | 손실 불가, 순간 폭주 흡수 |
| `onBackpressureDrop` | 새로 온 것부터 버림 | 최신성 무관, 손실 허용 |
| `onBackpressureLatest` | 최신 하나만 유지 | 실시간 값(센서·시세) |
| `onBackpressureError` | overflow 시 에러 신호 | fail-fast, 손실 감지 필요 |

### 꼬리질문 Q&A

**Q. Queue에 쌓인 요청이 너무 오래 대기하면 어떻게 처리하나요?**

**A.** **deadline을 넘긴 요청은 처리 전에 버린다 — 아무도 안 기다리는 응답을 만들지 않는 게 핵심.**
- 큐 항목에 TTL/enqueue 시각을 붙여, dequeue 시 deadline 초과면 즉시 폐기(load shedding).
- 과부하 시엔 **LIFO가 FIFO보다 유리할 수 있다** — 방금 들어온 요청이 아직 deadline 안에 살아있을 확률이 높기 때문. (관련 기법: CoDel / controlled delay — 원리는 맞으나 특정 프레임워크 기본 적용 여부는 **확인 안 됨**.)

**Q. Buffer 크기를 초과하는 요청이 계속 들어오면 사용자에게 어떤 응답을 줘야 할까요?**

**A.** **빠르게 거절(fail fast)한다 — 받아놓고 timeout 내는 것이 최악.**
- HTTP면 `503 Service Unavailable` 또는 `429 Too Many Requests` + `Retry-After` 헤더로 "지금 말고 나중에"를 명시.
- 받아서 무한정 대기시키면 ②~④ 연쇄를 스스로 부른다. **거절은 실패가 아니라 보호다.**

**Q. Backpressure와 rate limit은 어떤 차이가 있나요?**

**A.** **rate limit = 입구에서 정한 고정 상한(open loop), backpressure = 소비자 실시간 능력을 되먹이는 신호(closed loop).**

| | Rate limit | Backpressure |
|---|---|---|
| 위치 | 경계/입구 (admission control) | 소비자→생산자 내부 흐름 |
| 기준 | 정적 임계값 (예: 100 req/s) | 동적, 실제 소비 속도 |
| 방식 | 초과분 즉시 거절(429) | 생산 속도 자체를 늦춤 |
| 루프 | open loop (현재 부하 무시) | closed loop (피드백) |

- 서로 대체가 아니라 **보완**이다. rate limit은 남용·스파이크를 입구에서 쳐내고(내 실제 여유와 무관하게 캡), backpressure는 파이프라인 내부 속도를 자동 정합한다. 실무에선 둘 다 건다.

**Q. WebFlux에서 backpressure는 어떤 상황에서 의미가 있나요?**

**A.** **"빠른 생산자 + 느린 소비자 + 생산자를 늦출 수 있는" 세 조건이 맞을 때.**
- DB 스트리밍(R2DBC), 서버 간 스트림, SSE처럼 파이프라인 전 구간이 reactive면 `request(n)`이 소스까지 전파돼 효과가 있다.
- 반대로 **중간에 blocking(JPA/JDBC)이 끼면** 그 지점에서 흐름 제어가 끊겨 의미가 퇴색한다. 또 요청/응답 1건짜리(`Mono`)는 backpressure 얘기가 거의 무의미 — 스트림(`Flux`)에서 의미 있다.

**Q. 요청을 버리는 정책과 대기시키는 정책은 어떤 기준으로 선택하나요?**

**A.** **데이터의 "최신성 vs 완전성" + deadline 민감도로 가른다.**
- **버린다(drop/latest)**: 값이 금방 낡는 것(실시간 시세·센서·마우스 이벤트), 손실 허용, latency 최우선.
- **대기/버퍼(buffer)**: 손실 불가(결제·주문 이벤트), 순간 폭주지만 평균 부하는 감당 가능한 경우.
- 판단축: **idempotency(재시도 안전한가)**, **stale 데이터가 쓸모없나**, **deadline 안에 처리 가능한가**. 손실 불가한데 버퍼도 못 버티면 → 결국 입구에서 rate limit/거절로 λ를 줄이는 수밖에 없다.

### 🌱 심화 키워드
- **Reactive Streams `request(n)`** — 수요 기반 backpressure의 표준 신호. Publisher/Subscriber/Subscription/Processor 4개 인터페이스
- **Little's Law (L = λW)** — 큐 길이·도착률·체류시간의 관계. latency 증가를 정량으로 설명(안정 상태 기준)
- **Load shedding** — 과부하 시 일부 요청을 의도적으로 버려 전체를 지키는 기법
- **CoDel / LIFO queue** — 과부하 큐에서 오래된 요청을 버리고 신선한 요청을 우선하는 지연 제어
- **Circuit breaker** — 하류 포화를 감지해 호출을 끊어 연쇄 장애를 차단 (Resilience4j)
- **TCP flow control (sliding window)** — 네트워크 계층에 원래 있는 backpressure. 애플리케이션 backpressure의 원형

### 🔗 참고 자료
- Reactive Streams 규격(reactive-streams.org) — `Subscription.request`, backpressure 정의 (1차). "dynamic push-pull" 표현의 원문 귀속은 확인 필요
- Project Reactor 레퍼런스 — `onBackpressureBuffer/Drop/Latest/Error` 연산자
- AWS Builders' Library — load shedding·재시도(backoff·jitter) 관련 글 (정확한 문서명은 확인 필요)

### ❓ 더 파볼 질문

**Q. Kafka 컨슈머는 별도 backpressure 신호 없이 어떻게 흐름을 제어하나?**

**A.** 컨슈머가 `poll()`로 **당겨오는 pull 모델**이라, 처리가 느리면 poll을 덜 부르는 것 자체가 자연스러운 backpressure다. 다만 `max.poll.interval.ms` 안에 처리를 못 끝내면 컨슈머가 죽은 걸로 간주돼 리밸런싱이 터지므로, `max.poll.records`로 한 번에 가져올 양을 줄이는 게 실무 조절점이다.

**Q. 재시도 폭풍(retry storm)을 재시도 로직 자체로 완화하려면?**

**A.** 고정 간격 재시도는 부하를 동기화시켜 되레 스파이크를 만든다. **exponential backoff + jitter(무작위 지터)**로 재시도 시각을 분산시키고, **retry budget**(전체 요청 대비 재시도 비율 상한)으로 폭주를 막는다. circuit breaker가 열리면 아예 재시도를 멈추는 것도 방어다.

**Q. backpressure가 상류로 전파되다 결국 맨 앞 클라이언트까지 닿으면?**

**A.** 이상적이면 서버가 느려질 때 그 신호가 TCP window·`request(n)`을 타고 클라이언트까지 올라가 클라이언트가 스스로 전송을 늦춘다. 하지만 브라우저·모바일처럼 **협조하지 않는 클라이언트**는 이 신호를 무시하고 계속 쏘므로, 서버 입구의 rate limit·admission control이 최종 방어선이 된다.
