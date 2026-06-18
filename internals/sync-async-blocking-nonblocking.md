# 동기/비동기 · 블로킹/논블로킹 (스프링 예시로)

> **한 줄 정의:** *"블로킹/논블로킹은 **제어권을 바로 돌려주나**(호출자가 멈추나), 동기/비동기는 **완료를 호출자가 직접 챙기나 통지받나**"*. 둘은 **독립된 축**이라 4조합이 모두 가능하다.

> 관련 문서:
> - [../spring/spring-async-event-listener.md](../spring/spring-async-event-listener.md) — @Async/@EventListener의 결합도·스레드·시점 3축 (이 개념의 실전 적용)
> - [thread-pool.md](thread-pool.md) — @Async가 작업을 던지는 스레드 풀

---

## 1. 두 축이 각각 묻는 것 (흔한 오개념부터)

- ❌ **"비동기 = 스레드 분리"는 오개념.** 비동기의 본질은 스레드 분리가 아니다. 단일 스레드로도 비동기 가능(Node.js 이벤트 루프, `epoll`). 스레드 분리는 비동기를 *구현하는 한 방법*일 뿐.

| 축 | 진짜 묻는 것 | 키워드 |
|----|------------|--------|
| **블로킹 / 논블로킹** | 호출된 함수가 **제어권을 바로 돌려주나?** | 제어권·대기 |
| **동기 / 비동기** | 작업 **완료를 누가 챙기나?** (호출자가 직접 확인 vs 통지받음) | 완료·결과 처리 시점 |

- **블로킹**: 작업 끝날 때까지 제어권 안 줌 → 호출자 멈춤. **논블로킹**: 즉시 제어권 돌려줌 → 호출자 딴 일 가능.
- **동기**: 호출자가 결과를 **직접 확인하고 이어받음**(완료 시점=처리 시점). **비동기**: 끝나면 **콜백/Future로 따로** 통지받음(처리 시점 분리).

> 한 줄: **블로킹/논블로킹 = "내가 기다려야 하나?"(제어권)** / **동기/비동기 = "결과를 내가 챙기나, 통지받나?"(완료 처리)**

---

## 2. 4조합 — 스프링 예시로

| | 블로킹 | 논블로킹 |
|--|--------|---------|
| **동기** | `RestTemplate`, JDBC/JPA (가장 흔함) | 폴링 (`Future.isDone()` 루프) |
| **비동기** | `WebClient`+`.block()`, `future.get()` 즉시 호출 (거의 안 씀) | `WebClient`+콜백, `@Async`+`CompletableFuture` (가장 흔함) |

- **자연스러운 짝**(대각선): 동기+블로킹 / 비동기+논블로킹 → 그래서 평소 한 덩어리로 착각.
- **나머지 두 칸도 실재**: 동기+논블로킹(폴링), 비동기+블로킹(안티패턴에 가까움).

### ① 동기 + 블로킹 — 일반 호출 (가장 흔함)
```java
// RestTemplate은 응답 올 때까지 호출 스레드가 멈춰 기다림 → 결과를 직접 받아 이어감
ResponseEntity<User> res = restTemplate.getForEntity(url, User.class);
User u = res.getBody();          // 여기 올 땐 이미 완료
// JPA도 동일: repository.findById(id) 가 결과 올 때까지 블로킹
```

### ② 비동기 + 논블로킹 — 콜백 (가장 흔함)
```java
// WebClient(리액티브): 요청 던지고 호출 스레드는 즉시 다음 줄로 (논블로킹)
webClient.get().uri(url).retrieve()
    .bodyToMono(User.class)
    .subscribe(user -> log.info("도착: {}", user));   // 완료는 콜백으로 통지 (비동기)
log.info("난 안 기다리고 먼저 진행");                    // 이게 콜백보다 먼저 찍힐 수 있음

// @Async + CompletableFuture 도 같은 칸
@Async CompletableFuture<User> findAsync(Long id) { ... }   // 다른 스레드, 완료는 Future로
```

### ③ 동기 + 논블로킹 — 폴링
```java
CompletableFuture<Result> f = asyncService.submit(task);  // 즉시 반환 (논블로킹)
while (!f.isDone()) {        // 호출자가 직접 "다 됐어?" 반복 확인 (동기)
    doSomethingElse();       // 기다리는 동안 다른 일도 조금
}
Result r = f.join();
```
- 논블로킹 소켓 `read()`가 "아직 없음"을 즉시 반환 → `while`로 재시도(폴링)도 같은 칸.
- 폴링은 CPU를 헛돌릴 수 있어 잘 안 쓰지만, 대기가 짧거나 다른 일과 번갈아 할 땐 의미 있음.

### ④ 비동기 + 블로킹 — 안티패턴
```java
// WebClient는 비동기/논블로킹 모델인데 .block()으로 호출 스레드를 막아버림
User u = webClient.get().uri(url).retrieve()
    .bodyToMono(User.class)
    .block();    // ← 비동기로 만들어놓고 이점을 스스로 버림

// @Async 던지고 바로 .get() 도 같은 칸
CompletableFuture<User> f = service.findAsync(id);
User u2 = f.get();   // 즉시 블로킹 → 비동기 의미 사라짐
```
- 보통 **실수로** 이렇게 됨(async 코드에 무심코 `.block()`/`.get()`). 이득이 없어 거의 안 씀.

---

## 3. 이벤트·@Async와의 관계 — 이벤트는 이 축과 무관

스프링 이벤트를 보며 가장 헷갈리는 것: **"이벤트로 바꾸면 논블로킹 되나?" → 아니다.**

```
① mailService.send() 직접 호출           → 동기 + 블로킹
② publishEvent() + @EventListener        → 동기 + 블로킹  ← ①과 실행 흐름 동일!
③ publishEvent() + @Async @EventListener → 비동기 + 논블로킹
```

- **①과 ②는 실행상 똑같다.** 같은 스레드, 같은 트랜잭션, `publishEvent()`는 리스너가 끝날 때까지 블로킹. 차이는 **결합도(누가 호출하는지 모름)뿐.**
- **이벤트 = 결합도 축**(누가 호출), **블로킹 = 스레드 축**(어떻게 실행) → **무관.** "이벤트라서 블로킹/논블로킹"이라는 말 자체가 축을 섞은 것.
- **논블로킹/비동기 스위치는 오직 `@Async`.** 이벤트를 붙인다고 바뀌지 않는다.

### 왜 블로킹인가 — "같은 스레드는 한 번에 하나"가 증거 (★)

`@EventListener`(동기) 실행 흐름. 원 함수가 멈추고(블로킹) 리스너가 그 스레드를 빌려 돌고, 끝나야 재개:
```
[Thread-1] order() 실행 중
   save()
   publishEvent(event) ──┐ 같은 스레드가 order()를 "잠시 멈추고"
   [Thread-1] sendMail() 실행   ← order()는 여기서 대기(블로킹)
   publishEvent() 반환  ──┘ sendMail() 끝나야
   다음 줄 진행          ← 이제서야 order() 재개
```
- **한 스레드는 한 번에 하나만** 한다 → 리스너 도는 동안 원 함수는 동시에 못 돈다 → **그래서 블로킹일 수밖에 없다.** ("원 함수 진행 + 리스너 동시 실행"은 같은 스레드론 불가능.)
- 동시 진행(논블로킹)을 원하면 **스레드를 하나 더 빌려야** 한다 → 그 스위치가 `@Async`.

| | 동기/비동기 | 블로킹? | 비고 |
|--|--|--|--|
| 일반 함수 호출 | 동기 | **블로킹** | 대부분의 평범한 코드 |
| `@EventListener` | 동기 | **블로킹** | **일반 호출과 실행 동일** (결합도만 분리) |
| `@Async`(+이벤트든 직접이든) | 비동기 | 논블로킹 | 다른 스레드 빌림 |

> 즉 `@EventListener`가 동기+블로킹인 건 "이벤트라서"가 아니라 **"@Async가 없어서"**다. 그리고 평범한 서버 코드는 거의 다 동기+블로킹 — 비동기/논블로킹은 `@Async`·WebClient·리액티브를 **명시적으로** 써야 나온다.

---

> ## 📌 핵심 요약
> **블로킹/논블로킹**(제어권 바로 주나)과 **동기/비동기**(완료를 직접 챙기나 통지받나)는 **독립 축** → 4조합 모두 가능. 스프링: `RestTemplate`=동기블로킹, `WebClient`+콜백=비동기논블로킹, 폴링=동기논블로킹, `WebClient.block()`=비동기블로킹. "비동기=스레드분리"는 오개념. 스프링 이벤트는 이 축과 무관한 **결합도 축**이라, 논블로킹 전환 스위치는 `@Async`뿐.

> ## 🔗 참고 자료
> - 『토비의 스프링』·Spring 공식 *Web on Reactive Stack* (WebClient 논블로킹 모델)
> - 운영체제 교재의 I/O 모델 (blocking/non-blocking/IO multiplexing/async I/O)

> ## 🌱 심화 키워드
> - **I/O multiplexing (select/poll/epoll)** — 단일 스레드로 다중 논블로킹 I/O
> - **이벤트 루프(event loop)** — 스레드 분리 없이 비동기 (Node.js, Netty)
> - **CompletableFuture / 콜백 지옥 / 리액티브(Reactor)** — 비동기 결과 합성
> - **블로킹 I/O의 스레드 비용** — 요청당 스레드 모델 vs 이벤트 루프
> - **가상 스레드(Virtual Thread, Java 21)** — 블로킹 코드를 싸게

> ## ❓ 남은 질문
> 1. WebClient를 `.block()`으로 쓰면 RestTemplate과 뭐가 다를까? (스레드 점유 관점 — 차이 거의 없음)
> 2. 이벤트 루프는 "단일 스레드 비동기"인데, 그 안의 한 작업이 블로킹하면 전체가 멈추는 이유는?
> 3. 가상 스레드는 "블로킹처럼 쓰는데 논블로킹 효율"을 어떻게 달성하나? (캐리어 스레드 언마운트)
