# @Transactional 심화 (프록시 · 전파 · ThreadLocal)

> **한 줄 정의:** `@Transactional`은 *"프록시 AOP로 메서드를 감싸, 커넥션을 ThreadLocal에 묶어 한 트랜잭션으로 공유시키는"* 선언적 트랜잭션이다. 그 구조가 self-invocation·전파·비동기 함정의 뿌리다.

> 관련 문서:
> - [../database/transaction-and-isolation.md](../database/transaction-and-isolation.md) — 트랜잭션·격리수준·락의 토대
> - [../jpa/persistence-context-and-n-plus-one.md](../jpa/persistence-context-and-n-plus-one.md) — ThreadLocal에 묶이는 그 EntityManager(영속성 컨텍스트)
> - [./spring-async-event-listener.md](./spring-async-event-listener.md) — 커밋 이후 이벤트(@TransactionalEventListener)

---

## 1. 동작 원리 — 프록시 AOP

스프링은 시작 시 `@Transactional` 빈을 **프록시 객체(CGLIB 서브클래스 / JDK 동적 프록시)**로 감싸 **다른 빈엔 프록시를 주입**한다.

```
[다른 빈] ──order() 호출──> [프록시] ─① 트랜잭션 시작(TransactionInterceptor)
                                     └─② 실제 target.order() 실행 ─③ 커밋/롤백
```

- **외부 호출**은 프록시를 거치므로 인터셉터가 돌아 트랜잭션이 걸린다.

### self-invocation 함정 (★)
`order()` 안에서 `this.sendNotification()`을 부르면, **`this`는 프록시가 아니라 원본 target** → **프록시를 우회** → 인터셉터 미작동 → 내부 메서드의 `@Transactional`(예: `REQUIRES_NEW`)이 **무시**된다.

> 면접 답: *"프록시 AOP라서 내부 호출(`this`)은 프록시를 우회해 트랜잭션 어노테이션이 무시됩니다."*

**해결:** ① **별도 빈으로 분리**(권장, 외부 호출化) / ② 자기 프록시 주입(`@Lazy self`) / ③ `AopContext.currentProxy()`(`exposeProxy=true`) / ④ `TransactionTemplate`(프로그래밍 방식).

### CGLIB vs JDK 동적 프록시
| | JDK | CGLIB |
|---|---|---|
| 방식 | 인터페이스 프록시 | 서브클래스(바이트코드) |
| 조건 | 인터페이스 구현 필요 | 불필요 |
| 한계 | 인터페이스 메서드만 | **`final` 클래스/메서드 프록시 불가** |
| 기본 | (구버전) | **Spring Boot 2.0+ 기본** |

→ 둘 다 self-invocation엔 무력. CGLIB라 `final` 메서드 `@Transactional`은 조용히 안 먹는 함정.

---

## 2. 커넥션 공유 — TransactionSynchronizationManager + ThreadLocal (★ 핵심)

메서드 안 모든 DAO 호출이 어떻게 같은 트랜잭션이 되나?

```
order() 진입 → 1. DataSource에서 커넥션 획득 → 2. conn.setAutoCommit(false)
            → 3. 커넥션을 ThreadLocal에 바인딩 (TransactionSynchronizationManager)
  repoA.save() → DataSourceUtils.getConnection() → "내 스레드에 묶인 커넥션?" → 그거 재사용
  repoB.update()→ 〃 → 같은 커넥션 → 한 트랜잭션
            → 종료 시 commit()/rollback() + 커넥션 반납 + ThreadLocal 해제
```

- 트랜잭션 컨텍스트(커넥션, JPA면 `EntityManager`)는 **스레드에 매달려 있다(ThreadLocal)**.

### 🔥 나비효과: 스레드를 갈아타면 트랜잭션이 끊긴다
`@Async`·`new Thread`·병렬스트림·WebFlux 등 **스레드가 바뀌면 묶인 커넥션이 안 따라가** → 바깥 트랜잭션 **전파 불가**. → "트랜잭션과 비동기를 함부로 섞지 마라."

---

## 3. 전파(Propagation)

| 속성 | 진행 중 TX 있으면 | 없으면 | 쓰임 |
|------|------------------|--------|------|
| **REQUIRED**(기본) | **합류**(물리 TX 공유) | 새로 생성 | 대부분 |
| **REQUIRES_NEW** | **멈추고 새 TX**(별도 커넥션) | 새로 생성 | 독립 로깅/알림 |
| **NESTED** | **savepoint**(부분 롤백) | 새로 생성 | 일부만 롤백 |
| SUPPORTS | 합류 | TX 없이 | 조회성 |
| MANDATORY | 합류 | **예외** | TX 강제 |
| NEVER | **예외** | TX 없이 | TX 금지 |
| NOT_SUPPORTED | 멈추고 TX 없이 | TX 없이 | TX 회피 |

### 논리 트랜잭션 vs 물리 트랜잭션 (전파 이해의 틀 ★)
| | **물리 트랜잭션 (physical)** | **논리 트랜잭션 (logical)** |
|--|--|--|
| 정체 | **진짜 DB 트랜잭션** — 커넥션 1개 + `setAutoCommit(false)` … `commit()`/`rollback()` | 스프링이 추적하는 **`@Transactional` 단위 하나** |
| 레벨 | DB/커넥션 (실체) | 스프링 추상화 (개념) |
| 개수 | `REQUIRED` 합류 시 **1개**(공유) | `@Transactional` 메서드마다 1개 |

**스프링 규칙 두 줄:**
1. 물리 트랜잭션은 **자기에 속한 모든 논리 트랜잭션이 다 정상**이어야 커밋된다.
2. 논리 트랜잭션 **하나라도 rollback-only를 찍으면 → 물리 트랜잭션 전체 롤백.**

→ `REQUIRED`로 합류하면 **논리는 N개인데 물리는 1개(공유)**. 그래서 안쪽 논리가 찍은 낙인이 *공유 물리 TX*에 박혀, 바깥에서 예외를 삼켜도 안 지워진다(낙인은 예외 객체가 아니라 물리 TX에 있음).

### REQUIRED의 함정 — UnexpectedRollbackException (★)
`REQUIRED`는 **물리 트랜잭션을 공유**한다(논리 2개, 물리 1개). 안쪽 예외 시 안쪽 인터셉터가 공유 TX에 **rollback-only 낙인**을 찍음. **바깥에서 `catch`로 삼켜도 낙인은 안 지워져** → 바깥 커밋 시도 시 스프링이 낙인 발견 → **커밋 거부 + 강제 롤백 → `UnexpectedRollbackException`**.

```
order()[물리TX] ─ use()[REQUIRED 합류] 예외! → rollback-only 낙인 🔖
              ─ catch(삼킴) → 낙인 그대로 → 커밋 시도 → 거부 → 💥
```
- 독립시키려면 **`REQUIRES_NEW`**(별도 커넥션, 비용 주의) 또는 안쪽 **`@Transactional` 제거**(낙인 주체 제거).
- **REQUIRES_NEW = 별도 커넥션 추가 점유** → 루프 남발 시 커넥션 풀 고갈(비관적 락과 같은 병).
- **NESTED** = savepoint 부분 롤백, 별도 커넥션 X, 단 **JPA(JpaTransactionManager) 미지원**.

---

## 4. readOnly = true — 실질 최적화 3가지

1. **JPA 더티 체킹 스킵(최대):** FlushMode를 MANUAL로 → flush·스냅샷 생략 → CPU/메모리 절약.
2. **실수 방지:** 의도치 않은 UPDATE 차단.
3. **읽기 분산:** `conn.setReadOnly(true)` 힌트 → `readOnly` TX는 **Replica로 라우팅**(`AbstractRoutingDataSource` + `LazyConnectionDataSourceProxy` + `isCurrentTransactionReadOnly()`).

---

> ## 📌 핵심 요약
> `@Transactional`은 **프록시 AOP**(self-invocation 무력) + **ThreadLocal 커넥션 바인딩**(스레드 갈아타면 끊김) 구조다. `REQUIRED`는 물리 TX를 공유해 안쪽 예외가 **rollback-only 낙인**을 남겨 바깥 catch에도 `UnexpectedRollbackException`을 낸다. 독립은 `REQUIRES_NEW`(별도 커넥션). `readOnly`는 flush·더티체킹을 끄고 Replica 라우팅 기준이 된다.

> ## 🔗 참고 자료
> - 『토비의 스프링 3.1』 6장(AOP·트랜잭션) — 프록시·전파 원리 한국어 표준
> - Spring 공식: *Transaction Propagation* / *Declarative Transaction Implementation*

> ## 🌱 심화 키워드
> - **논리 트랜잭션 vs 물리 트랜잭션** — 전파 이해의 틀
> - **rollback-only / globalRollbackOnly** — UnexpectedRollbackException 원인
> - **DataSourceUtils / ConnectionHolder** — 스레드-커넥션 바인딩 실제 클래스
> - **LazyConnectionDataSourceProxy / AbstractRoutingDataSource** — readOnly 읽기 분산
> - **FlushMode (AUTO/COMMIT/MANUAL)** — readOnly가 건드리는 것
> - **OSIV** — 영속성 컨텍스트 수명 논쟁(→ jpa 노트)

> ## ❓ 남은 질문
> 1. `@Async`에서 트랜잭션이 필요하면? (메서드 내부에서 새 트랜잭션, 전파 불가 인지)
>
>    → **답:** @Async는 새 스레드로 실행돼 호출자의 트랜잭션(ThreadLocal 바인딩)이 전파되지 않는다. 비동기 메서드에 `@Transactional`을 따로 붙여 그 스레드에서 **새 트랜잭션**을 열어야 하고, 호출자와 원자적으로 묶이지 않음을 감안해야 한다.
> 2. 읽기 분산에서 "쓰기 직후 읽기"가 Replica 지연으로 옛 값이면? (→ 복제 지연 = CAP·최종 일관성)
>
>    → **답:** 복제는 비동기라 쓰기 직후 Replica는 옛 값을 볼 수 있다(최종 일관성). 방금 쓴 데이터는 Primary에서 읽도록 라우팅(read-your-writes)하거나, 세션 스티키·동기 복제·지연 감안 재시도로 완화한다.
