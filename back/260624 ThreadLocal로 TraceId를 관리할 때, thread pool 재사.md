# 260624 ThreadLocal로 TraceId를 관리할 때, thread pool 재사용 환경에서는 어떤 cleanup이 필요할까요?

ThreadLocal로 TraceId를 관리할 때, thread pool 재사용 환경에서는 어떤 cleanup이 필요할까요?

실무에서 로그 추적을 위해
요청마다 traceId, requestId, userId 같은 값을 MDC나 ThreadLocal에 넣어두는 경우가 많습니다.

그런데 여기서 놓치기 쉬운 포인트가 하나 있습니다.

서버는 요청마다 새로운 스레드를 만드는 게 아니라,
대부분 thread pool의 스레드를 재사용합니다.

즉, 이전 요청에서 넣어둔 ThreadLocal 값을 제대로 지우지 않으면
다음 요청 로그에 이전 사용자의 trace 정보가 섞이는 문제가 생길 수 있습니다.

이 질문은 단순히 ThreadLocal 개념을 아는지보다,
운영 환경에서 thread pool이 어떻게 재사용되고, 그로 인해 어떤 로그/보안/디버깅 문제가 생길 수 있는지 확인하는 질문에 가깝습니다.

같이 체크해보면 좋은 포인트는 아래와 같습니다.

- ThreadLocal은 thread 단위로 값이 저장된다는 점
- WAS나 Executor의 thread pool은 스레드를 재사용한다는 점
- 요청 완료 후 remove()로 값을 정리해야 한다는 점
- 예외가 발생해도 cleanup이 되도록 finally에서 제거해야 한다는 점
- 비동기 처리, @Async, WebFlux, Coroutine 환경에서는 컨텍스트 전파 방식이 달라질 수 있다는 점

꼬리질문으로는 이런 질문이 이어질 수 있습니다.

- ThreadLocal은 내부적으로 어떻게 값을 저장하나요?
- ThreadLocal.remove()를 호출하지 않으면 어떤 문제가 생기나요?
- MDC는 ThreadLocal과 어떤 관계가 있나요?
- @Async나 별도 Executor로 넘어가면 TraceId는 유지되나요?
- WebFlux 같은 reactive 환경에서는 왜 ThreadLocal 기반 로깅이 어려울까요?

---

## 답변

> **한 줄 핵심**: ThreadLocal 값은 "요청"이 아니라 "스레드"에 붙어 있고 풀의 스레드는 요청이 끝나도 죽지 않는다 — 그래서 ① 요청 경계 finally에서 remove/clear, ② 스레드가 바뀌는 지점마다 명시적 복사·정리, 이 두 가지 cleanup이 필요하다.

### 1문 1답

**Q. ThreadLocal은 thread 단위로, 내부적으로 어떻게 값을 저장하나요?**
→ 값의 실소유자는 ThreadLocal이 아니라 Thread다. 각 Thread 객체가 자기만의 ThreadLocalMap을 들고 있고, ThreadLocal 인스턴스를 key로, 저장한 값을 value로 담는다. 그래서 같은 ThreadLocal 변수를 여러 스레드가 함께 써도 서로의 값을 볼 수 없다 — 스레드마다 별도의 map이기 때문이다. 그런데 이 entry에서 key는 ThreadLocal에 대한 약참조인 반면 value는 강참조라, ThreadLocal 객체가 GC되어 key가 사라져도 value는 스레드가 살아있는 한 map에 그대로 남을 수 있다. 이 참조의 비대칭이 뒤에 나올 메모리 누수 문제의 기술적 근원이다.

**Q. WAS나 Executor의 thread pool이 스레드를 재사용하는 것이 왜 문제가 되나요?**
→ 서버는 요청마다 새 스레드를 만드는 게 아니라 대부분 스레드 풀의 스레드를 꺼내 재사용한다. 그런데 ThreadLocal 값은 "요청"이 아니라 "스레드"에 붙어 있고, 풀 스레드는 요청이 끝나도 죽지 않고 다음 요청을 처리하러 돌아온다. 그래서 이전 요청에서 넣어 둔 traceId나 userId를 지우지 않으면 그 값이 다음 요청에 그대로 노출된다. 이는 다른 사용자의 trace가 로그에 섞이는 오염 문제이고, 만약 사용자 컨텍스트나 권한 정보를 ThreadLocal로 관리했다면 권한 오적용 같은 보안 문제로까지 번질 수 있다. 즉 스레드 재사용은 성능을 위한 정상 동작이지만, cleanup을 빠뜨리면 그 재사용이 곧 데이터 누출 경로가 된다.

**Q. 요청 완료 후 remove()로 값을 정리하지 않으면 어떤 문제가 생기나요?**
→ 두 가지 문제가 함께 생긴다. 첫째는 데이터 오염으로, 풀 환경에서 지우지 않은 값이 다음 요청으로 새어 로그가 뒤섞이거나 잘못된 사용자 컨텍스트가 적용된다. 둘째는 메모리 누수로, value가 강참조라 remove하지 않으면 스레드가 살아있는 한 회수되지 않는다. 특히 위험한 상황은 WAS에 웹앱을 재배포할 때인데, 풀 스레드의 ThreadLocal value가 이전 웹앱의 클래스를 참조하고 있으면 그 클래스로더 전체가 GC되지 못한다. 그러면 재배포를 반복할수록 메타스페이스나 힙이 차오르는 클래스로더 누수로 이어질 수 있다.

**Q. 예외가 발생해도 cleanup되도록 finally에서 제거해야 하는 이유는 무엇인가요?**
→ 요청 경계에서 값을 넣더라도, 요청 처리 도중 예외가 나면 뒤에 있는 정리 코드가 실행되지 않고 건너뛸 수 있기 때문이다. 문제는 예외가 난 요청을 처리하던 스레드도 죽지 않고 그대로 풀로 돌아간다는 점이다. 그래서 정상 경로에서만 지우면, 예외가 난 순간의 오염된 값이 그대로 남아 다음 요청으로 넘어간다. 이를 막으려면 필터나 인터셉터에서 진입 시 값을 넣고, finally 블록에서 remove()나 MDC.clear()를 호출해 정상·예외 경로 모두에서 cleanup이 보장되게 해야 한다.

**Q. MDC는 ThreadLocal과 어떤 관계가 있나요?**
→ MDC는 로깅 프레임워크(Logback/Log4j2)가 제공하는 key-value 저장소인데, 그 내부 구현이 바로 ThreadLocal이다. 로그 패턴에 쓰는 %X{traceId} 같은 표기는 현재 스레드의 MDC에서 값을 읽어 찍는 방식으로 동작한다. 구현이 ThreadLocal이라는 것은 곧 ThreadLocal의 약점을 그대로 물려받는다는 뜻이다. 즉 스레드 재사용에 따른 오염과, 스레드가 바뀔 때 값이 전파되지 않는 단절 문제를 똑같이 겪는다. 그래서 MDC를 쓸 때도 요청 경계에서 MDC.clear()가, 스레드 전환 지점에서 TaskDecorator를 통한 전파가 필요하다.

**Q. @Async나 별도 Executor로 넘어가면 TraceId는 유지되나요?**
→ 자동으로는 유지되지 않는다. 실행 스레드가 호출자와 다르고, ThreadLocal 값은 스레드 사이에 자동으로 복사되지 않기 때문이다. 유지하려면 명시적으로 전파해야 하는데, TaskDecorator로 작업 제출 시점의 MDC 컨텍스트맵을 캡처해 실행 스레드에 넣어 주거나, Micrometer Tracing(구 Sleuth)의 context propagation을 적용하는 방법이 있다. 이때 중요한 것은 실행이 끝난 뒤 반드시 clear까지 해줘야 한다는 점이다. 전파만 하고 지우지 않으면 오히려 오염 문제를 비동기 스레드 풀로까지 확산시키는 셈이 되기 때문이다.

**Q. WebFlux 같은 reactive 환경에서는 왜 ThreadLocal 기반 로깅이 어려울까요?**
→ reactive 환경에서는 "한 요청 = 한 스레드"라는 전제 자체가 무너지기 때문이다. reactive 파이프라인은 하나의 요청이 이벤트 루프와 여러 스케줄러의 스레드를 옮겨 다니며 처리되어, 어느 한 스레드의 ThreadLocal에 값을 넣어도 다음 연산자는 다른 스레드에서 실행될 수 있다. 그래서 ThreadLocal에 담아 둔 traceId가 다음 단계에서는 그냥 사라져 버린다. 이를 해결하기 위해 Reactor는 스레드가 아니라 구독 체인에 붙어 다니는 Context(contextWrite)를 제공한다. 로그에 MDC로 노출하려면 context-propagation 라이브러리나 연산자 훅으로 "각 연산 실행 직전 Context→MDC 복사, 직후 정리"를 걸어 줘야 한다.

### 면접 답변 (구술용)

문제의 근거부터 말씀드리면, ThreadLocal 값은 요청이 아니라 스레드에 붙어 있는데 WAS는 스레드 풀의 스레드를 재사용합니다. 스레드가 요청이 끝나도 죽지 않으니 지우지 않은 traceId나 userId가 다음 요청에 그대로 노출됩니다 — 다른 사용자의 trace가 섞이는 로그 오염이고, 사용자 컨텍스트를 ThreadLocal로 관리했다면 권한 오적용 같은 보안 문제로도 갈 수 있습니다. 필요한 cleanup은 두 가지입니다. 첫째, 요청 경계에서 넣고 반드시 finally에서 지웁니다 — 필터에서 진입 시 MDC.put, 응답 완료 시 finally 블록에서 MDC.clear를 하는데, finally가 필수인 이유는 예외가 난 요청의 스레드도 풀로 돌아가기 때문입니다. 둘째, 스레드가 바뀌는 지점마다 명시적으로 전파합니다 — @Async나 별도 Executor로 넘어가면 새 스레드에는 값이 없으므로, TaskDecorator로 제출 시점의 MDC를 캡처해 실행 스레드에 넣고 실행 후 지우는 래핑을 걸어줍니다. Micrometer Tracing 같은 프레임워크를 쓰면 이 전파를 대신해 줍니다.

### 원리 이해 (왜 그런가)

**ThreadLocal 내부 구조 — 모든 문제의 근거:**

```
Thread 객체 ──▶ 자기만의 ThreadLocalMap 보유
                key   = ThreadLocal 인스턴스 (약참조, weak)
                value = 저장한 값 (강참조, strong)
```

값의 실소유자는 ThreadLocal이 아니라 **Thread**입니다. "스레드가 살아있는 한 값도 살아있다" — 풀 환경에서 스레드는 사실상 영원히 사니까, remove하지 않은 값도 영원히 삽니다. key가 약참조라 ThreadLocal 객체가 GC돼도 value는 map에 남을 수 있다는 점이 메모리 누수의 기술적 근거입니다.

**cleanup이 필요한 두 지점:**

| 지점 | 문제 | 해법 |
|------|------|------|
| 요청 경계 (같은 스레드 재사용) | 이전 요청 값이 다음 요청에 노출 | 필터/인터셉터에서 설정 + **finally에서 remove()/MDC.clear()** (예외 경로 포함) |
| 스레드 전환 (@Async, Executor) | 새 스레드에는 값이 아예 없음 | **TaskDecorator**: 제출 시점 MDC 컨텍스트맵 캡처 → 실행 스레드에 set → 실행 후 clear |

주의: InheritableThreadLocal은 답이 아닙니다 — 복사가 "스레드 생성 시점"에 일어나는데, 풀 스레드는 요청과 무관한 과거에 이미 생성됐기 때문입니다.

### 꼬리질문 Q&A

**Q. ThreadLocal은 내부적으로 어떻게 값을 저장하나요?**
→ **각 Thread가 자기 ThreadLocalMap을 갖고, ThreadLocal 인스턴스를 key로 값을 저장한다.**
그래서 같은 ThreadLocal 변수를 여러 스레드가 써도 서로의 값을 볼 수 없습니다. entry의 key는 ThreadLocal에 대한 약참조지만 value는 강참조라서, key가 GC되어도 value는 스레드가 살아있는 한 map에 남을 수 있습니다 — 이 비대칭이 누수 문제의 근원입니다.

**Q. remove()를 호출하지 않으면 어떤 문제가 생기나요?**
→ **① 풀 환경에서 다음 요청으로 값이 새는 데이터 오염, ② value가 회수되지 않는 메모리 누수.**
특히 WAS에 웹앱을 재배포할 때가 위험합니다 — 풀 스레드의 ThreadLocal value가 이전 웹앱의 클래스를 참조하고 있으면 그 클래스로더 전체가 GC되지 못해서, 재배포를 반복하면 메타스페이스/힙이 차오르는 클래스로더 누수로 이어질 수 있습니다.

**Q. MDC는 ThreadLocal과 어떤 관계인가요?**
→ **MDC는 로깅 프레임워크(Logback/Log4j2)가 제공하는 key-value 저장소인데, 내부 구현이 ThreadLocal이다.**
로그 패턴의 `%X{traceId}`가 현재 스레드의 MDC에서 값을 읽어 찍는 방식입니다. 구현이 ThreadLocal이므로 재사용 오염과 전파 단절 문제를 똑같이 상속받고, 그래서 MDC.clear()와 TaskDecorator가 필요합니다.

**Q. @Async나 별도 Executor로 넘어가면 TraceId는 유지되나요?**
→ **자동으로는 안 된다 — 실행 스레드가 다르고 ThreadLocal은 스레드 간 복사되지 않기 때문.**
TaskDecorator로 MDC 컨텍스트맵을 복사하거나 Micrometer Tracing(구 Sleuth)의 context propagation을 적용해야 합니다. 이때 실행이 끝난 뒤 clear까지 해야 합니다 — 전파만 하고 안 지우면 오염 문제를 비동기 풀로 확산시키는 셈이 됩니다.

**Q. WebFlux 같은 reactive 환경에서는 왜 ThreadLocal 기반 로깅이 어려울까요?**
→ **"한 요청 = 한 스레드"라는 전제가 무너지기 때문.**
reactive 파이프라인은 하나의 요청이 이벤트 루프와 스케줄러의 여러 스레드를 옮겨 다니며 처리됩니다. 어느 스레드의 ThreadLocal에 넣어도 다음 연산자는 다른 스레드에서 실행될 수 있습니다. 그래서 Reactor는 스레드가 아니라 구독 체인에 붙어 다니는 Context(`contextWrite`)를 제공하고, 로그에 MDC로 노출하려면 context-propagation 라이브러리나 연산자 훅으로 "실행 직전 Context→MDC 복사, 직후 정리"를 해줘야 합니다.

### 🌱 심화 키워드
- **ThreadLocalMap / 약참조 entry** — 누수 메커니즘의 내부 구조
- **TaskDecorator** — 스프링에서 Executor에 컨텍스트 복사 로직을 끼워 넣는 표준 지점
- **Micrometer Tracing (구 Spring Cloud Sleuth)** — traceId 생성·전파를 프레임워크 레벨에서 처리
- **Reactor Context / context-propagation** — 스레드 대신 구독 체인에 컨텍스트를 싣는 reactive의 답
- **Scoped Values** — Virtual Thread 시대에 ThreadLocal을 대체하려는 JDK의 새 메커니즘 (JEP 시리즈로 진행 중)

### 🔗 참고 자료
- SLF4J/Logback 공식 문서 — MDC 챕터
- Micrometer Tracing 공식 문서 — context propagation
- Java API 문서 — ThreadLocal, InheritableThreadLocal

### ❓ 더 파볼 질문
- **InheritableThreadLocal은 왜 풀 환경에서 무용지물인가?**
  ↳ 부모→자식 복사가 "자식 스레드를 생성하는 순간"에 일어나기 때문이다. 풀의 스레드는 애플리케이션 기동 초기에 이미 만들어졌고 이후엔 재사용만 되므로, 요청 시점의 값이 복사될 기회 자체가 없다.
- **Virtual Thread 환경에서 ThreadLocal은 어떤 부담이 되나?**
  ↳ VT는 요청당 하나씩 수십만 개가 생길 수 있는데, 각 VT가 자기 ThreadLocalMap을 가지므로 ThreadLocal에 무거운 객체(버퍼, 포맷터 캐시 등)를 넣는 패턴은 메모리 사용량을 폭증시킨다. 그래서 "공유 불변 데이터"용으로는 Scoped Values가 대안으로 제시되고 있다.
- **Reactor의 context-propagation은 실제로 어느 시점에 ThreadLocal을 복원하나?**
  ↳ Micrometer의 context-propagation 라이브러리가 Reactor 연산자 훅에 스냅샷 복원 로직을 걸어, 각 연산자가 실행되기 직전에 Reactor Context의 값을 ThreadLocal(MDC)로 옮기고 실행 후 원상 복구한다. "구독 체인의 값이 실행 순간마다 스레드로 잠깐 내려온다"고 이해하면 된다.
