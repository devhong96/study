# 260703 Virtual Thread를 WebFlux나 Coroutine의 대안으로 고려한다면, 어떤 점을 비교해야 할까요?

Virtual Thread를 WebFlux나 Coroutine의 대안으로 고려한다면, 어떤 점을 비교해야 할까요?

요즘 Java 21 이후로 Virtual Thread 이야기가 많이 나오면서
“이제 WebFlux 안 써도 되는 거 아닌가요?”
“Coroutine 대신 Virtual Thread 쓰면 되는 거 아닌가요?”
같은 질문이 면접에서도 충분히 나올 수 있습니다.

이 질문은 단순히 Virtual Thread 개념을 아는지보다,
동시성 모델을 선택할 때 처리 방식, 코드 복잡도, I/O 특성, 운영 비용을 비교할 수 있는지 확인하는 질문에 가깝습니다.

같이 체크해보면 좋은 포인트는 아래와 같습니다.

- Virtual Thread는 blocking 코드를 유지하면서도 많은 동시 요청을 적은 비용으로 처리하기 위한 Java 런타임 기능
- WebFlux는 event loop 기반 non-blocking/reactive 프로그래밍 모델
- Coroutine은 suspend 기반으로 비동기 코드를 동기 코드처럼 작성할 수 있게 해주는 Kotlin의 경량 동시성 모델
- DB Driver, 외부 API Client, 라이브러리가 blocking인지 non-blocking인지에 따라 선택 기준이 달라짐
- 성능뿐 아니라 코드 가독성, 디버깅, 팀 러닝커브, 운영 지표 관찰 가능성도 함께 고려해야 함

꼬리질문으로는 이런 질문이 이어질 수 있습니다.

- Virtual Thread를 쓰면 모든 blocking 문제가 해결되나요?
- WebFlux를 쓰면서 JPA를 그대로 사용하면 어떤 문제가 생기나요?
- Virtual Thread와 Platform Thread의 차이는 무엇인가요?
- Event Loop에서 blocking 작업이 발생하면 어떤 문제가 생기나요?
- 기존 Spring MVC 애플리케이션에서 Virtual Thread를 도입할 때 주의할 점은 무엇인가요?

---

## 답변

> **한 줄 핵심**: 셋 다 "I/O 대기 중인 스레드가 자원을 잠식하는 문제"를 푸는 다른 답이다 — VT는 "스레드를 싸게", WebFlux는 "스레드가 안 기다리게", Coroutine은 "suspend로 동기처럼". 비교 축은 성능 수치가 아니라 **의존 라이브러리의 blocking 여부, 코드 복잡도·팀 러닝커브, 필요한 기능(backpressure), 운영 관측성**이다.

### 1문 1답

**Q. Virtual Thread를 WebFlux나 Coroutine의 대안으로 고려한다면, 어떤 점을 비교해야 할까요?**

**A.** 셋 다 "I/O 대기 중인 스레드가 자원을 잠식하는 문제"를 푸는 다른 답이다 — VT는 스레드를 싸게(blocking 코드를 그대로 두고 JVM이 carrier 스레드에 얹어 blocking 시 unmount), WebFlux는 스레드가 안 기다리게(이벤트 루프+reactive), Coroutine은 suspend로 동기처럼 쓰는 방식이다. 비교 축은 성능 수치가 아니라 네 가지다. 첫째이자 가장 결정적으로 의존 라이브러리가 blocking인가 — JPA/JDBC 중심이면 VT가 자연스럽고 WebFlux는 이점이 사라진다. 둘째, 코드 복잡도·팀 러닝커브로 VT는 거의 0인 반면 WebFlux는 팀 전체 전환이 필요하다. 셋째, 필요한 기능 — 세밀한 backpressure나 스트림 합성이 요구사항이면 여전히 WebFlux/Flow가 우위다. 넷째, 운영 관측성(디버깅·스레드 덤프 방식)이 달라진다. 마지막으로 VT의 함정도 짚어야 하는데, CPU 바운드에는 이점이 없고 synchronized 안에서 blocking하면 pinning이 생기며(JDK 21~23), 스레드 상한이 사라지므로 DB 풀 같은 하위 자원 보호를 다시 설계해야 한다.

**Q. Virtual Thread는 무엇을 위한 기능인가요?**

**A.** Virtual Thread는 blocking 코드와 thread-per-request 모델을 그대로 유지하면서도 많은 동시 요청을 적은 비용으로 처리하려는 Java 21의 정식 런타임 기능(JEP 444)입니다. 동작 원리는 JVM이 수십만 개의 VT를 소수의 carrier(플랫폼) 스레드 위에 얹어 스케줄링하는 것입니다. VT가 blocking I/O를 만나면 JVM이 그 VT를 carrier에서 내리고(unmount, 스택은 힙에 보관) carrier는 다른 VT를 실행하다가, I/O가 끝나면 원래 VT를 다시 마운트합니다. 그래서 blocking이 더 이상 스레드 하나를 통째로 잠그지 않고 값싸집니다. 최대 강점은 JDBC 같은 기존 명령형 코드를 거의 그대로 두면서도 동시 수용량을 얻는다는 점입니다.

**Q. WebFlux는 어떤 동시성 모델인가요?**

**A.** WebFlux는 이벤트 루프와 reactive 스트림을 기반으로 모든 I/O를 non-blocking으로 조립하는 프로그래밍 모델입니다. 발상은 "스레드가 아예 기다리지 않게 하자"는 것으로, 스레드를 늘리는 대신 대기 자체를 없앱니다. 그 결과 backpressure와 스트리밍 합성이 일급 기능으로 제공되는 것이 고유한 강점입니다. 대신 코드 전체가 reactive 체인이어야 하고, 중간에 blocking 호출이 하나만 섞여도 그 루프가 막혀 전체가 무너지는 "오염성"이 있습니다. 또 스택트레이스가 조각나 디버깅에 전용 기법이 필요하다는 운영상의 부담도 따릅니다.

**Q. Coroutine은 어떤 동시성 모델인가요?**

**A.** Coroutine은 suspend를 이용해 비동기 코드를 마치 동기 코드처럼 순차적으로 작성하게 해주는 Kotlin의 경량 동시성 모델입니다. suspend 지점에서 스레드를 반납하기 때문에 가볍고, 콜백 지옥 없이 읽기 좋은 코드를 유지할 수 있습니다. 고유 강점은 부모-자식 스코프로 취소와 에러가 자동 전파되는 structured concurrency입니다. 다만 진짜로 non-blocking이 되려면 하부 호출까지 suspend여야 하고, 하부가 blocking이면 앞서 본 VT 이전과 같은 스레드 점유 문제가 그대로 남습니다. 그래서 코루틴을 쓴다고 자동으로 non-blocking이 되는 것은 아니라는 점을 유의해야 합니다.

**Q. 의존 라이브러리가 blocking이냐 non-blocking이냐가 선택에 어떤 영향을 주나요?**

**A.** 비교 축 중 첫째이자 가장 결정적인 것이 의존 라이브러리가 blocking이냐 non-blocking이냐입니다. 애플리케이션이 JPA/JDBC를 중심으로 돌아간다면, blocking 코드를 그대로 태워도 unmount로 값싸게 처리하는 VT가 가장 자연스러운 선택입니다. 반대로 이 상황에서 WebFlux를 택하면 non-blocking의 이점이 사라지는데, 이벤트 루프 위에서 JDBC가 스레드를 붙잡아버리기 때문입니다. WebFlux의 이점은 DB 드라이버까지 R2DBC 같은 non-blocking으로 끝까지 맞춰야 비로소 성립합니다. 그래서 "내 스택의 I/O 라이브러리가 무엇인가"가 모델 선택을 좌우합니다.

**Q. 성능 외에 어떤 관점(가독성·디버깅·러닝커브·관측성)을 함께 비교해야 하나요?**

**A.** 동시성 모델 선택은 처리량 수치만으로 결정할 수 없고, 코드 복잡도와 팀 러닝커브, 디버깅 난이도, 필요한 기능, 운영 관측성을 함께 저울질해야 합니다. VT는 기존 명령형 코드를 그대로 쓰므로 러닝커브가 거의 0이고 스택트레이스도 기존과 유사해 디버깅이 익숙합니다. 반면 WebFlux는 팀 전체가 reactive 사고방식으로 전환해야 하고 스택이 조각나 관측이 어렵습니다. 그렇지만 세밀한 backpressure나 스트림 합성이 요구사항으로 존재한다면 여전히 WebFlux나 Coroutine의 Flow가 우위입니다. 결국 "성능"이 아니라 "무엇이 필요하고 팀이 무엇을 감당할 수 있는가"가 선택의 실제 기준이 됩니다.

**Q. Virtual Thread를 쓰면 모든 blocking 문제가 해결되나요?**

**A.** 아니오입니다. VT가 해결하는 것은 정확히 "blocking 대기가 플랫폼 스레드를 낭비하는 문제" 하나뿐입니다. synchronized 블록 안에서 blocking하면 VT를 unmount하지 못해 carrier가 통째로 잠기는 pinning(JDK 21~23의 제약), CPU 바운드 작업, 하위 자원 고갈 같은 문제는 그대로 남습니다. 특히 하위 자원 고갈은 오히려 악화될 수 있는데, 톰캣 max-threads가 해주던 암묵적 동시성 상한이 사라지면서 커넥션 풀 앞에 몰리는 동시 요청이 폭증할 수 있기 때문입니다. 그래서 VT 도입 시에는 세마포어 등으로 하위 자원 보호를 다시 설계해야 합니다.

**Q. WebFlux를 쓰면서 JPA를 그대로 사용하면 어떤 문제가 생기나요?**

**A.** WebFlux에서 JPA를 그대로 쓰는 것은 구조적으로 최악의 조합입니다. 이벤트 루프 스레드는 보통 코어 수만큼밖에 없는데, JPA/JDBC는 쿼리 응답이 올 때까지 그 귀한 스레드를 붙잡아 둡니다. 루프 하나가 막히면 그 루프에 배정된 모든 커넥션의 이벤트 처리가 정지하므로, 소수의 요청만으로 전체 서버가 멈출 수 있습니다. boundedElastic 같은 별도 스케줄러로 blocking을 격리할 수는 있지만, 그러면 그 풀 크기가 곧 동시성 상한이 되어 결국 "스레드 풀 기반 MVC와 같은 구조 + reactive 복잡도"만 남습니다. 그래서 WebFlux를 쓸 거라면 드라이버까지 R2DBC 등 non-blocking으로 맞춰야 이점이 성립합니다.

**Q. Virtual Thread와 Platform Thread의 차이는 무엇인가요?**

**A.** Platform Thread는 OS 스레드와 1:1로 매핑되어 스택을 미리 확보하는데, 통상 1MB 안팎이라 현실적으로 수천 개가 상한입니다. Virtual Thread는 JVM이 스케줄링하는 경량 스레드로, 스택을 힙에 작게 시작해 필요할 때만 키우므로 수십만 개까지 만들 수 있습니다. 하지만 본질적인 차이는 개수가 아니라 "blocking의 비용"입니다. PT는 blocking이 발생하면 OS 스레드 하나가 그대로 잠기지만, VT는 unmount로 carrier를 다른 VT에 양보하므로 blocking이 값싸집니다. 그래서 VT는 CPU 연산보다 I/O 대기가 많은 요청 처리에 정확히 들어맞는 도구입니다.

**Q. Event Loop에서 blocking 작업이 발생하면 어떤 문제가 생기나요?**

**A.** 이벤트 루프에서 blocking 작업이 발생하면, 그 루프가 감시하던 수천 개 커넥션의 이벤트 처리가 전부 지연되거나 정지합니다. 이벤트 루프 모델의 대전제는 "루프 위에서는 절대 기다리지 않는다"는 것이고, 이 규율을 어기는 코드 단 한 줄이 전체 장애로 번집니다. 스레드를 늘려 해결하는 구조가 아니기 때문에, 루프가 막히면 대안 없이 그대로 밀립니다. 이것은 Redis에서 긴 Lua 스크립트 하나가 서버 전체를 멈추게 하는 것과 완전히 같은 구조입니다. 그래서 이 모델에서는 blocking 호출을 별도 스케줄러로 격리하는 규율이 필수입니다.

**Q. 기존 Spring MVC 애플리케이션에서 Virtual Thread를 도입할 때 주의할 점은 무엇인가요?**

**A.** Spring Boot 3.2+에서는 spring.threads.virtual.enabled=true 한 줄로 VT를 켤 수 있지만, 그 전에 네 가지를 점검해야 합니다. 첫째, 오래된 커넥션 풀이나 드라이버는 내부에 synchronized가 많아 pinning을 유발하므로 최신 버전으로 올리고, 자체 코드의 synchronized+I/O 구간은 ReentrantLock으로 교체합니다(JDK 21~23 기준). 둘째, 톰캣 max-threads가 하던 암묵적 보호가 사라지므로 하위 자원 앞에 세마포어 같은 명시적 동시성 제한을 다시 둡니다. 셋째, 요청당 VT가 하나씩 생기므로 무거운 객체를 ThreadLocal에 캐싱하던 패턴은 메모리 폭증을 일으킬 수 있어 점검이 필요합니다. 넷째, -Djdk.tracePinnedThreads로 pinning을 감지하고 메트릭·스레드 덤프 도구가 VT를 지원하는지 확인하는 등 관측 체계를 갖춰야 합니다.

### 면접 답변 (구술용)

세 기술은 같은 문제를 서로 다른 방식으로 풉니다. Virtual Thread는 "스레드를 싸게 만들자"는 접근입니다 — blocking 코드와 thread-per-request 모델을 그대로 두고, JVM이 VT를 소수의 carrier 스레드에 얹어서 blocking 호출을 만나면 그 지점에서 내려(unmount) 다른 VT에 양보합니다. 기존 코드와 JDBC를 거의 그대로 쓰면서 동시 수용량을 얻는 게 최대 강점입니다. WebFlux는 "스레드가 기다리지 않게 하자"는 접근으로, 이벤트 루프와 reactive 스트림으로 모든 I/O를 non-blocking으로 조립합니다. backpressure와 스트리밍이 일급 기능인 대신 코드 전체가 reactive여야 하고 디버깅이 어렵습니다. Coroutine은 suspend로 비동기를 동기 문법처럼 쓰는 Kotlin의 답이고, structured concurrency가 고유 강점입니다. 비교해야 할 축은 네 가지입니다 — 첫째이자 가장 결정적으로, 의존 라이브러리가 blocking인가: JPA/JDBC 중심이면 VT가 자연스럽고 WebFlux는 이점이 사라집니다. 둘째, 코드 복잡도와 팀 러닝커브 — VT는 거의 0, WebFlux는 팀 전체의 전환이 필요합니다. 셋째, 필요한 기능 — 세밀한 backpressure나 스트림 합성이 요구사항이면 여전히 WebFlux/Flow가 우위입니다. 넷째, 운영 관측성 — 디버깅·스레드 덤프 방식이 달라집니다. 마지막으로 VT의 함정도 짚어야 합니다: CPU 바운드에는 이점이 없고, synchronized 안에서 blocking하면 pinning이 생기며(JDK 21~23), 스레드 상한이 사라지므로 DB 풀 같은 하위 자원 보호를 다시 설계해야 합니다.

### 원리 이해 (왜 그런가)

**3모델 비교표:**

| | Virtual Thread | WebFlux | Coroutine |
|---|---|---|---|
| 발상 | 스레드를 싸게 (JEP 444, Java 21 정식) | 스레드가 안 기다리게 (이벤트 루프) | suspend로 동기 문법 유지 |
| blocking 시 | JVM이 VT를 carrier에서 unmount | **금지** — 루프가 막히면 전체 붕괴 | suspend면 스레드 반납, blocking이면 VT 이전과 동일 문제 |
| 코드 스타일 | 기존 명령형 그대로 | reactive 체인 (오염성 — 중간에 blocking 하나면 무너짐) | 동기처럼 보이는 suspend 함수 |
| 스택트레이스/디버깅 | 기존과 유사 | 조각남, 전용 기법 필요 | 비교적 양호 (코루틴 디버거) |
| 고유 강점 | JDBC 등 기존 생태계 재사용 | backpressure, 스트리밍 합성 | structured concurrency, Kotlin 생태계 |
| 주요 함정 | pinning, ThreadLocal 폭증, 상한 소멸 | blocking 혼입, 러닝커브 | 진짜 non-blocking이 되려면 하부도 suspend여야 |

**VT의 동작 원리 (왜 blocking이 싸지나):**

```
VT 수십만 개  ──스케줄링──▶  carrier(플랫폼) 스레드 소수 (기본 ≈ 코어 수)
VT가 blocking I/O 호출 → JVM이 그 VT를 carrier에서 내림(unmount, 스택은 힙에 보관)
                       → carrier는 다른 VT 실행 → I/O 완료되면 VT 다시 마운트
※ pinning: synchronized 블록 안에서 blocking하면 unmount 불가 → carrier가 통째로 잠김
  (JDK 21~23의 제약. JDK 24의 JEP 491에서 해소된 것으로 알고 있음 — 거의 확실)
```

**잊기 쉬운 결정적 포인트 — VT는 동시성 "상한"을 없애는 기술이다**: 톰캣 max-threads가 해주던 암묵적 admission control이 사라지므로, DB 커넥션 풀·외부 API 같은 하위 자원 보호를 세마포어 등으로 다시 설계해야 합니다. 상한이 사라지면 하위 자원으로 몰리는 동시 요청은 오히려 폭증할 수 있습니다.

### 꼬리질문 Q&A

**Q. Virtual Thread를 쓰면 모든 blocking 문제가 해결되나요?**

**A.** **아니오 — 해결되는 것은 "blocking 대기가 플랫폼 스레드를 낭비하는 문제"뿐이다.**
pinning(synchronized + blocking, 일부 네이티브 호출), CPU 바운드 작업, 하위 자원 고갈은 그대로 남습니다. 특히 마지막은 악화될 수 있습니다 — 스레드 상한이라는 병목이 사라지면서 커넥션 풀 앞에 몰리는 동시 요청이 폭증할 수 있기 때문입니다.

**Q. WebFlux에서 JPA를 그대로 쓰면 어떤 문제가 생기나요?**

**A.** **이벤트 루프 스레드는 코어 수만큼밖에 없는데, JPA/JDBC가 그 스레드를 쿼리 응답까지 잡아둔다 — 소수 요청만으로 전체 서버가 멈추는 구조적 최악.**
루프 하나가 막히면 그 루프에 배정된 모든 커넥션의 이벤트 처리가 정지합니다. boundedElastic 같은 별도 스케줄러로 격리해도 그 풀 크기가 동시성 상한이 되어, 결국 "스레드 풀 기반 MVC와 같은 구조 + reactive 복잡도"만 남습니다. WebFlux를 쓸 거면 드라이버까지 R2DBC 등 non-blocking이어야 이점이 성립합니다.

**Q. Virtual Thread와 Platform Thread의 차이는?**

**A.** **PT는 OS 스레드와 1:1(스택 미리 확보, 통상 1MB 안팎, 현실 상한 수천 개), VT는 JVM이 스케줄링하는 경량 스레드(스택을 힙에 작게 시작, 수십만 개 가능).**
본질적 차이는 "blocking의 비용"입니다 — PT는 blocking이 OS 스레드 하나를 잠그지만, VT는 unmount로 넘어가므로 blocking이 싸집니다. 그래서 VT는 "I/O 대기가 많은 요청 처리"에 정확히 맞는 도구입니다.

**Q. Event Loop에서 blocking 작업이 발생하면?**

**A.** **그 루프가 감시하던 수천 커넥션의 이벤트 처리가 전부 지연·정지된다.**
이벤트 루프 모델의 대전제가 "루프 위에서는 절대 기다리지 않는다"이고, 이를 어기는 코드 한 줄이 전체 장애가 됩니다. Redis에서 긴 Lua가 위험한 것(260701)과 완전히 같은 구조입니다.

**Q. 기존 Spring MVC에 Virtual Thread를 도입할 때 주의점은?**

**A.** **Boot 3.2+에서 `spring.threads.virtual.enabled=true`로 켜되, 네 가지를 점검해야 한다.**
① synchronized 병목 — 오래된 커넥션 풀·드라이버는 synchronized가 많아 pinning을 유발하므로 최신 버전으로 올리고, 자체 코드의 synchronized+I/O 구간은 ReentrantLock으로 교체(JDK 21~23 기준). ② 동시성 상한 재설계 — 톰캣 max-threads가 하던 보호가 사라지므로 하위 자원 앞에 세마포어 등 명시적 제한. ③ ThreadLocal 점검 — 요청당 VT 1개라 무거운 객체를 ThreadLocal에 캐싱하는 패턴은 메모리 폭증(→ 260624). ④ 관측 — pinning 감지(`-Djdk.tracePinnedThreads`), 메트릭·덤프 도구의 VT 지원 확인.

### 🌱 심화 키워드
- **carrier thread / mount·unmount** — VT 스케줄링의 실체
- **pinning / JEP 491** — synchronized와 VT의 충돌, JDK 24에서의 해소
- **structured concurrency** — 코루틴의 강점이자 Java에도 도입 중인 개념(JEP 시리즈)
- **boundedElastic** — WebFlux에서 blocking을 격리하는 스케줄러(그리고 그 한계)
- **R2DBC** — reactive 스택을 끝까지 성립시키는 non-blocking DB 드라이버

### 🔗 참고 자료
- JEP 444 (Virtual Threads, openjdk.org) — 설계 의도와 한계가 가장 정확하게 적힌 1차 자료
- Spring Boot 3.2 공식 문서/블로그 — spring.threads.virtual.enabled
- Project Reactor 공식 문서 — 스케줄러와 blocking 격리

### ❓ 더 파볼 질문
- **VT의 스케줄러는 무엇이고 어떻게 동작하나?**
  ↳ 전용 ForkJoinPool(work-stealing 방식, 캐리어 수 기본 ≈ 코어 수)이 VT를 carrier에 배정한다. work-stealing이라 특정 carrier가 놀면 다른 큐의 VT를 훔쳐와 실행한다 — CPU를 놀리지 않는 구조라는 점에서 Dispatchers.Default와 같은 계열이다.
- **pinning은 실제로 어떻게 진단하나?**
  ↳ JVM 옵션 `-Djdk.tracePinnedThreads=full`(21~23)로 pinning 발생 시 스택을 출력하거나, JFR의 `jdk.VirtualThreadPinned` 이벤트로 수집한다. "pinning이 있는지 모른 채 켜는 것"이 도입 실패의 전형이라 사전 측정이 중요하다.
- **VT 시대에도 여전히 풀링이 필요한 자원은?**
  ↳ 스레드는 싸졌지만 DB 커넥션, 파일 핸들, 외부 API 쿼터 같은 하위 자원은 여전히 유한하다. 즉 "스레드 풀"은 사라져도 "커넥션 풀 + 세마포어"는 남는다 — 풀링의 대상이 스레드에서 진짜 희소 자원으로 이동했다고 정리할 수 있다.
