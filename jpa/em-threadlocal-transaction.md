# EntityManager · ThreadLocal · 트랜잭션 — 영속성 컨텍스트는 어떻게 스레드에 묶이나

> **한 줄 정의:** 주입되는 `EntityManager`는 *"진짜가 아니라 싱글톤 프록시(호출벨)"*고, 진짜 영속성 컨텍스트는 *"트랜잭션마다 새로 생겨 그 스레드의 **ThreadLocal**에 묶이는 작업자"*다. 변경 감지(dirty checking)부터 `@Async`가 깨지는 이유까지 전부 이 구조에서 나온다.

> 관련 문서:
> - [persistence-context-and-n-plus-one.md](persistence-context-and-n-plus-one.md) — 1차 캐시·readOnly·LazyInitializationException·OSIV
> - [second-level-cache.md](second-level-cache.md) — 1차 캐시가 TX를 못 넘는 한계를 메우는 2차 캐시
> - [../spring/transactional-deep-dive.md](../spring/transactional-deep-dive.md) — `@Transactional` 프록시·전파

---

## 0. 한눈에 보는 흐름 (한 줄기)

이 노트의 모든 개념은 *"엔티티 하나 고쳤는데 UPDATE가 나간다"*에서 출발해 바닥까지 내려간 **한 줄기**다.

```
① 변경 감지 — update() 안 불렀는데 UPDATE?
     dirty checking: 영속 진입 시 스냅샷 → flush(커밋 직전)에 비교 → 변경분 UPDATE
     (readOnly = 이 스냅샷을 끔)
        │  "그 스냅샷·1차 캐시를 들고 있는 게 누구냐?"
        ▼
② 주입된 EM은 가짜다
     @Autowired EntityManager = 싱글톤 프록시(호출벨). 컨텍스트를 직접 안 듦.
     호출될 때마다 "지금 이 스레드에 묶인 진짜 EM"을 찾아 위임.
        │  "어디서 찾는데?"
        ▼
③ ThreadLocal — 스레드별 사물함
     진짜 EM은 @Transactional 시작 때 생겨 그 스레드의 ThreadLocal에 바인딩.
     스레드=일꾼 / ThreadLocal=열쇠. 값은 각 Thread의 캐비닛(ThreadLocalMap)에.
     캐비닛=스레드당 1개, 서랍=N개(set()시 런타임 생성), static인 이유=열쇠 공유.
        │  "그래서 뭐가 가능/불가능해지나?"
        ▼
④ 세 가지 귀결 (전부 이 구조에서 파생)
     · 같은 TX = 같은 컨텍스트 (프록시가 늘 같은 진짜 EM을 찾음)
     · @Async는 깨진다 (다른 스레드=다른 캐비닛=빈 EM 서랍 → 준영속 → LazyInit예외)
     · 반납 사고 (스레드 재사용 + 서랍 안 비움 → 보안오염·자원/메모리 누수 → remove() 철칙)
        │  "EM·컨텍스트·트랜잭션은 정확히 무슨 사이?"
        ▼
⑤ 관계 정리 (가게 비유)
     트랜잭션=영업시간(수명 경계) / 진짜EM=점원 / 영속성컨텍스트=장바구니(EM과 한몸)
     프록시EM·EMF=영구 호출벨·공장(장바구니 없음)
     트랜잭션이 컨텍스트 수명을 정함: 시작=생성, 커밋=flush후 소멸 → TX끝=준영속
     ✗오개념: "싱글톤 빈이라 이미 장바구니를 든다" → 싱글톤은 공장·호출벨뿐, 컨텍스트는 TX마다 새로
```

> **한 문장으로:** 변경 감지가 가능한 건 영속성 컨텍스트가 스냅샷을 들고 있어서고, 그 컨텍스트는 **트랜잭션마다 새로 생겨 ThreadLocal로 스레드에 묶이며**, 주입받는 EM은 그 진짜 컨텍스트를 **매번 찾아 연결해주는 싱글톤 창구**일 뿐이다. → dirty checking · readOnly · @Async 깨짐 · OSIV 커넥션 점유 · ThreadLocal 누수가 **같은 구조의 다른 얼굴**.

---

## 1. 변경 감지(dirty checking) — `update()`도 안 불렀는데 UPDATE가 나가는 이유

엔티티를 조회해 필드만 바꾸고 커밋했는데 UPDATE가 나간다. 원인은 **dirty checking + 스냅샷**.

- **스냅샷을 언제 뜨나?** → 엔티티가 **영속 상태로 들어오는 순간**(DB 로드돼 1차 캐시 적재 시) "최초 값"을 따로 복사.
- **언제 비교하나?** → **flush 시점**(보통 *커밋 직전*, 그 외 JPQL 실행 전·명시적 `flush()` 시). 현재 엔티티 ↔ 스냅샷 필드별 비교 → 다르면 UPDATE를 쓰기지연 저장소에 만들어 전송.
- **`readOnly`가 끄는 게 바로 이 스냅샷이다.** `@Transactional(readOnly=true)` → FlushMode를 MANUAL로 + 스냅샷 보관 생략 → 변경 감지 안 함 + 메모리 절약.
- 기본 UPDATE는 **변경 컬럼만이 아니라 전체 컬럼**. 바꾸려면 `@DynamicUpdate`.

> 즉 "왜 자동 UPDATE?" = 영속 진입 시 스냅샷 복사 → flush에 비교 → 변경분 UPDATE.

---

## 2. 주입된 EntityManager는 "진짜"가 아니다 — 프록시 + ThreadLocal

`@Autowired EntityManager em`으로 주입되는 건 **싱글톤 공유 프록시**(SharedEntityManagerCreator). 그 자체엔 영속성 컨텍스트가 없다.

```
em.persist(x) 호출
   │
   ▼  프록시가 매 호출마다 묻는다:
   "지금 이 스레드에 트랜잭션에 묶인 진짜 EntityManager가 있나?"
   │
   ▼
TransactionSynchronizationManager  ← 내부가 ThreadLocal<Map<EMF, EMHolder>>
   │  (@Transactional 시작 때 진짜 EM을 만들어 현재 스레드 칸에 꽂아둠)
   ▼
있으면 → 그 진짜 EM에 위임 (그래서 같은 TX 안에선 늘 같은 컨텍스트)
없으면 → 임시 EM 하나 만들어 한 번 쓰고 버림
```

- **왜 ThreadLocal?** 트랜잭션은 *한 스레드가 처음부터 끝까지* 처리한다는 게 스프링의 전제. 그 스레드에 자원(EM·커넥션)을 매달아두면 서비스→리포지토리가 파라미터 없이 같은 자원을 공유한다. `@Transactional`·1차 캐시·커넥션 바인딩이 전부 이 위에 선다.
- **`@Async`가 깨지는 이유**: 다른 스레드로 던지면 그 스레드의 ThreadLocal엔 원래 EM이 없다 → 넘긴 엔티티는 준영속 → 지연로딩 시 `LazyInitializationException`. 트랜잭션도 `@Async` 경계를 전파하지 못한다.

---

## 3. 스레드 vs ThreadLocal — 헷갈리면 여기서 막힌다

| | **Thread (스레드)** | **ThreadLocal** |
|--|--|--|
| 정체 | **일을 실행하는 일꾼** | **값을 "스레드마다 따로" 담는 보관 장치(열쇠)** |
| 개수 | 요청 처리만큼(풀에서 빌림) | 보통 `static` 하나. 근데 스레드마다 다른 값을 돌려줌 |
| 생성 | 톰캣이 풀에 미리 만듦 | 객체(열쇠)는 클래스 로딩 때 1번 |

### 진짜 저장은 각 Thread 객체 안에 있다 (오개념 1순위)

값은 ThreadLocal "안"이 아니라 **각 Thread 객체 안의 `ThreadLocalMap`(캐비닛)**에 있다.

```
Thread A 객체 → 캐비닛 { [EM 서랍]→EM_A, [커넥션 서랍]→커넥션_A, [시큐리티 서랍]→로그인_A }
Thread B 객체 → 캐비닛 { [EM 서랍]→EM_B, ... }

ThreadLocal 객체 = 위 캐비닛을 여는 "열쇠"(모든 스레드가 같은 열쇠 공유)
```

`threadLocal.get()` = **"지금 이 코드를 돌리는 스레드의 캐비닛을, 이 열쇠로 연다."** 같은 `get()`인데 A가 부르면 EM_A, B가 부르면 EM_B. → `@Async`로 스레드가 바뀌면 그 캐비닛의 EM 서랍이 **비어 있다**(아무도 안 넣었으니까). "넣은 놈과 꺼내는 놈이 다르면 못 꺼낸다."

### 캐비닛 1개 + 서랍 N개

- **ThreadLocalMap(캐비닛)은 스레드당 1개.**
- 그 안 **서랍(ThreadLocal 값 칸)은 여러 개** — EM용·커넥션용·시큐리티용 따로. 서랍끼리는 **완전히 독립**(하나 지워도 나머지 그대로).

### 서랍 개수는 언제 정해지나 → "미리 안 정해진다"

- **후보 열쇠**(앱의 모든 `static ThreadLocal` 필드)는 클래스 로딩 때 존재.
- 하지만 **실제 서랍**은 그 스레드가 해당 ThreadLocal에 처음 `set()` 하는 순간 lazy 생성, `remove()`하면 사라짐. → 요청이 타는 코드 경로에 따라 **런타임에 증감**(emergent).
- 내부 구현: `ThreadLocalMap`은 `Entry[]` 해시테이블, 작게 시작해 필요 시 리사이즈. 미리 N칸 안 잡음.

```
요청 디스패치  → RequestContextHolder.set()   ← [요청정보 서랍]
시큐리티 필터  → SecurityContextHolder.set()   ← [로그인 서랍]
@Transactional → bindResource()                ← [EM 서랍][커넥션 서랍]
요청 끝         → 각자 remove()                 ← 서랍 정리
```

### ThreadLocal은 왜 `static final`인가

ThreadLocal은 **열쇠 객체**고, 그걸 `static final` 필드에 담는 이유는 **모든 스레드가 같은 열쇠 하나를 공유**해야 "넣은 값을 같은 열쇠로 다시 꺼내기"가 성립하기 때문. (요청마다 `new` 하면 열쇠가 매번 달라져 오작동/누수.) → "static이라서 ThreadLocal"이 아니라, "ThreadLocal을 공유하려고 static에 둔다."

---

## 4. EM ↔ 영속성 컨텍스트 ↔ 트랜잭션 (가게 비유)

| 개념 | 비유 | 실체 | 수명 |
|------|------|------|------|
| **트랜잭션** | 영업 시간(open~close) | DB 작업의 시간 경계 | — |
| **(진짜) EntityManager** | 일하는 점원 | 영속성 컨텍스트를 든 주체 | 트랜잭션마다 새로 |
| **영속성 컨텍스트** | 점원이 든 장바구니 | 1차 캐시 + 스냅샷 | EM과 한 몸 |
| **(프록시) EntityManager** | 손님용 호출벨 | `@Autowired` 싱글톤 | 영구(앱 수명) |
| **EntityManagerFactory** | 점원 찍어내는 공장 | 싱글톤 | 영구 |

- **진짜 EM 1개 ↔ 영속성 컨텍스트 1개** (한 몸). EM은 API 손잡이, 컨텍스트는 내용물.
- **트랜잭션이 진짜 EM의 수명을 정한다**(스프링 기본 = 트랜잭션 범위 영속성 컨텍스트):
  ```
  @Transactional 진입 → 진짜 EM 생성(빈 장바구니) + 커넥션 확보 → ThreadLocal 바인딩
  ... 작업(조회→1차캐시, 변경→스냅샷 대기) ...
  커밋 → flush(변경분 UPDATE) → DB commit → EM close + 커넥션 반납 + 서랍 정리
  ```
  트랜잭션 시작=컨텍스트 생성, 커밋=flush 후 소멸. → TX 끝나면 엔티티가 준영속이 되는 이유.

> **핵심 오개념 교정**: "EM이 싱글톤 빈이니 이미 장바구니를 들고 있다" → 틀림. **싱글톤인 건 공장(EMF)·호출벨(프록시)뿐**, 둘 다 장바구니가 없다. **영속성 컨텍스트(진짜 EM)는 트랜잭션마다 새로** 찍어낸다. 그래서 TX마다 1차 캐시가 깨끗하게 비어 시작.

### 커넥션·EM 바인딩 타이밍 (OSIV에 따라)

```
OSIV ON (부트 기본 true)
  요청 시작 → 진짜 EM 생성 + ThreadLocal 바인딩 (커넥션은 아직 X, lazy)
  @Transactional → DB 커넥션 확보 + 트랜잭션 시작
  요청 끝 → EM 닫고 정리
OSIV OFF
  요청 시작 → 깨끗
  @Transactional → EM 생성 + 커넥션 확보 + 바인딩 → TX 끝나면 즉시 반납
```
- DB 커넥션은 어느 쪽이든 **실제 쿼리/트랜잭션이 필요할 때 lazy**하게 잡는다(요청 시작만으로 점유 X).

---

## 5. ThreadLocal 반납 사고 — 왜 `remove()`가 철칙인가

톰캣은 스레드를 **풀에서 빌려 쓰고 반납**한다(스레드는 안 사라짐). 이전 요청이 서랍을 안 비우고 반납하면, 다음 요청이 같은 스레드를 빌려 쓸 때:

1. **보안/데이터 오염** — A의 `SecurityContext`가 남아 B가 `get()` 하면 A의 로그인 정보 → B가 A로 행세. (실제 사고)
2. **자원 누수** — 이전 EM·커넥션이 남아 혼동/커넥션 미반납.
3. **메모리 누수** — WAS가 스레드를 영원히 재사용 → 안 비운 객체가 GC 안 되고 쌓임(클래스로더 누수).

→ `try { set(...) } finally { remove() }`가 철칙. 스프링은 트랜잭션/필터가 이 정리를 대신 해줘서 우리가 직접 안 할 뿐.

---

> ## 📌 핵심 요약
> 주입된 EM은 **싱글톤 프록시(호출벨)**, 진짜 영속성 컨텍스트는 **트랜잭션마다 생겨 그 스레드의 ThreadLocal에 묶이는 작업자**. ThreadLocal은 "열쇠", 값은 각 Thread의 캐비닛(`ThreadLocalMap`, 스레드당 1개)에 서랍으로 저장되며 서랍은 `set()` 시 런타임 생성. 트랜잭션이 컨텍스트의 수명을 정하고(시작=생성, 커밋=flush후 소멸), 스레드를 바꾸면(`@Async`) 캐비닛이 달라 컨텍스트가 안 따라간다. 반납 전 `remove()`는 철칙.

> ## 🔗 참고 자료
> - 김영한 『자바 ORM 표준 JPA 프로그래밍』 — 영속성 컨텍스트·플러시
> - Spring Framework Reference — *Transaction Management* / `TransactionSynchronizationManager`, `OpenEntityManagerInViewInterceptor`
> - JDK 소스 — `java.lang.ThreadLocal` / `ThreadLocalMap` (Entry[] 해시테이블 구조)

> ## 🌱 심화 키워드
> - **SharedEntityManagerCreator** — 주입되는 프록시 EM의 정체
> - **TransactionSynchronizationManager** — 트랜잭션 자원을 스레드에 바인딩하는 ThreadLocal 허브
> - **ThreadLocalMap / Entry[] / WeakReference key** — ThreadLocal 내부 구조와 메모리 누수
> - **트랜잭션 범위 영속성 컨텍스트 vs 확장 영속성 컨텍스트(EXTENDED)**
> - **FlushMode (AUTO/COMMIT/MANUAL)** — readOnly가 건드리는 부분
> - **@DynamicUpdate / @DynamicInsert** — 변경 컬럼만 SQL 생성

> ## ❓ 남은 질문
> 1. 트랜잭션 자원 ThreadLocal에 EM 말고 같이 바인딩되는 핵심 자원(커넥션)은 OSIV ON일 때 왜 위험한가? (→ N+1 노트 OSIV와 연결)
>
>    → **답:** OSIV ON이면 영속성 컨텍스트와 바인딩된 DB 커넥션이 트랜잭션 종료가 아니라 **HTTP 응답 끝까지** 유지된다. 뷰 렌더링·외부 API 대기 동안에도 커넥션을 쥐고 있어 트래픽이 몰리면 커넥션 풀이 빨리 고갈된다.
> 2. `ThreadLocalMap`의 key가 `WeakReference`인데도 메모리 누수가 나는 이유는? (value는 strong ref라는 점)
>
>    → **답:** key(ThreadLocal)는 약참조라 GC되지만 **value는 강참조**로 엔트리에 남는다. 스레드 풀처럼 스레드가 오래 재사용되면 key=null인 죽은 엔트리의 value가 계속 살아 누수된다. 그래서 사용 후 `remove()`가 필수.
> 3. 트랜잭션 전파 `REQUIRES_NEW`는 같은 스레드에서 도는데 영속성 컨텍스트/커넥션은 어떻게 분리될까?
>
>    → **답:** 스프링이 기존 트랜잭션의 자원(EM·커넥션)을 잠시 **대피(suspend)**시키고 새 커넥션·새 영속성 컨텍스트로 별도 트랜잭션을 연 뒤, 끝나면 원래 것을 복원한다. 같은 스레드라도 자원 묶음을 갈아끼워 독립적으로 커밋/롤백된다.
