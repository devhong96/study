# 낙관적 락 vs 비관적 락 (@Version & 동시성 제어)

> **한 줄 정의:** 동시 수정으로 갱신이 덮어써지는 *갱신 분실(Lost Update)*을 막는 두 갈래 — **낙관적 락**은 *"충돌 드물 거라 믿고 락 없이 진행, 커밋 때 `@Version`으로 검사 → 충돌이면 예외 던지고 재시도"*, **비관적 락**은 *"충돌 잦다 보고 읽을 때 DB 행 락을 걸어 다른 트랜잭션을 대기(블로킹)"*시킨다.

> 관련 문서:
> - [../database/transaction-and-isolation.md](../database/transaction-and-isolation.md) — Lost Update 등 이상현상·격리수준 (이 문제의 출처)
> - [persistence-context-and-n-plus-one.md](persistence-context-and-n-plus-one.md) — OSIV에서 본 "자원 오래 점유 → 커넥션 풀 고갈"(비관적 락의 위험과 같은 병)

---

## 1. 문제 — 갱신 분실 (Lost Update)

재고 100개에서 두 요청이 동시에 1개씩 주문:

```java
@Transactional
void order(Long productId) {
    Product p = repo.findById(productId);  // 둘 다 stock=100 읽음
    p.setStock(p.getStock() - 1);          // 둘 다 99로 계산
    // 커밋 → 둘 다 99로 UPDATE  → 98이어야 하는데 99 💥
}
```

```
T1: stock=100 읽음
T2: stock=100 읽음    ← T1 커밋 전. 둘 다 "100"을 봄
T1: 99로 UPDATE·커밋
T2: 99로 UPDATE·커밋   ← T1의 갱신을 못 보고 덮어씀 = "갱신 분실"
```

- 이름: **갱신 분실(Lost Update)**. ("레이스 컨디션"은 이를 포함하는 일반 개념.)
- 원인: **read → modify → write가 원자적이지 않음.** 읽기와 쓰기 사이에 끼어든 갱신이 덮어써진다.

---

## 2. 두 갈래의 메커니즘

### 낙관적 락 (Optimistic) — 락 안 걸고 버전 검사
엔티티에 `@Version` 컬럼을 둔다.
```java
@Version private Long version;
```
UPDATE 시 Hibernate가 버전 조건을 붙임:
```sql
UPDATE product SET stock=99, version=6 WHERE id=? AND version=5
```
- 그 사이 누가 바꿔 `version`이 6이 됐으면 → **영향받은 행 0개 → `OptimisticLockException`** → 애플리케이션이 **잡아서 재시도**.
- 읽기~UPDATE 사이엔 락을 안 잡으므로 서로 막지 않음(동시성↑).

### 비관적 락 (Pessimistic) — 읽을 때 DB 락
```java
repo.findById(id, LockModeType.PESSIMISTIC_WRITE);  // SELECT ... FOR UPDATE
```
- 행에 쓰기 락을 걸고, 다른 트랜잭션은 락이 풀릴 때까지 **대기(블로킹)**.
- 앞 트랜잭션이 커밋/롤백하면 다음 차례가 진행.

### 2-1. 낙관적 락은 어떻게 동시에도 안 깨지나 (= CAS)

**함정**: 만약 "SELECT version → 앱에서 비교 → UPDATE"라면 두 트랜잭션이 둘 다 5를 읽고 둘 다 통과시켜 **똑같이 갱신 분실**이 난다. → **앱에서 비교하면 안 된다.**

**진짜 메커니즘**: 검사를 앱이 아니라 **UPDATE 문의 `WHERE version=5`에 넣어** 원자화하고, **DB 행 쓰기 락**이 동시 UPDATE를 순차 처리한다.
```
T1, T2 둘 다 version=5 읽음
T1: UPDATE ... WHERE version=5 → 행 쓰기 락 획득 → 5→6 → 커밋 → 락 해제 (영향 1건)
T2: UPDATE ... WHERE version=5 → T1 락 동안 대기 → 진행 시 version=6이라 매칭 0건
                                → OptimisticLockException
```
→ **둘 다 성공 불가. 정확히 하나만 성공, 나머지는 0건→예외.**

- **이건 본질적으로 CAS(Compare-And-Set):** `WHERE version=5`=compare, `SET version=6`=set, 행 락=원자성, 실패(0건)→재시도. CAS 루프와 동형.
- **"락을 안 쓴다"가 아니라 "락 점유 기간을 점(UPDATE 찰나)으로 줄였다"가 정확:**
  | | 락 점유 기간 |
  |--|--|
  | 비관적 | `SELECT FOR UPDATE` ~ **커밋까지 내내** (길게) |
  | 낙관적 | `UPDATE` 문 **실행되는 찰나만** (읽기~UPDATE 사이엔 락 없음) |
  - 낙관적의 높은 동시성은 여기서 나온다.

---

## 3. ⚠️ 가장 헷갈리는 지점 — 누가 "예외"고 누가 "대기"인가

| | **낙관적 락** | **비관적 락** |
|--|--|--|
| 충돌 시 동작 | **예외(`OptimisticLockException`) 던짐** → 재시도 필요 | **대기(블로킹)** — 락 풀릴 때까지 기다렸다 진행 |
| 예외? | 충돌이 곧 예외 | 정상 흐름엔 예외 없음 (타임아웃·데드락 때만) |

> 흔한 오해: "비관적 락이 접근 시 오류를 반환" → **틀림.** 오류(예외)를 던지고 재시도가 필요한 건 **낙관적 락**. 비관적은 **막고 기다린다.**

---

## 4. 트레이드오프 — "그냥 비관적으로 밀면 안 되나?"

| | **낙관적 락** | **비관적 락** |
|--|--|--|
| 락 | 안 검 (커밋 때 버전 검사) | 행 락을 **트랜잭션 내내 점유** |
| 동시성 | **높음**(서로 안 막음) | **낮음**(직렬화 — 줄 세움) |
| 위험 | 충돌 잦으면 **재시도 폭증** | **블로킹 → 스레드·커넥션 점유 → 풀 고갈·데드락** |
| 적합 | 충돌이 **드물 때**(대부분) | 충돌이 **잦고** 재시도 비용이 클 때 |

- **무조건 비관적이 더 위험할 수 있다(직관과 반대):** 락 점유 동안 다른 요청이 줄 서서 대기 → 트래픽 몰리면 스레드·커넥션이 쌓여 **커넥션 풀 고갈**(OSIV에서 본 그 병) + **데드락** 위험. 동시성을 깔아뭉개 처리량 추락.
- **낙관적의 재시도가 서버를 터뜨리려면 충돌이 아주 잦아야** 하는데, 낙관적을 고르는 상황 자체가 "충돌 드묾"이라 재시도가 거의 안 일어나 싸다. (반대로 충돌이 진짜 잦으면 그땐 낙관적이 손해 → 비관적이 나음.)
- **결론**: 갈림길은 **충돌 빈도**. 대부분 충돌이 드무니 **낙관적이 기본**, **잦은 핫스팟에서만 비관적**.

### 실무 한 수 — 단순 증감은 원자적 UPDATE
재고 차감·카운터처럼 단순 연산이면 락보다 이게 1순위:
```sql
UPDATE product SET stock = stock - 1 WHERE id = ? AND stock > 0
```
- read-modify-write를 **한 문장**으로 만들어 race 자체를 제거. (영향 행 0이면 재고 부족 처리.)

---

> ## 📌 핵심 요약
> 동시 수정으로 갱신이 덮어써지는 **갱신 분실**을 막는 두 방법 — **낙관적**(락X·`@Version` 검사·충돌 시 **예외→재시도**, 충돌 드물 때 기본)과 **비관적**(`SELECT … FOR UPDATE`·**대기(블로킹)**, 충돌 잦은 핫스팟). "오류 반환"은 비관적이 아니라 낙관적. 무조건 비관적은 블로킹으로 동시성·커넥션을 죽인다. 단순 증감은 **원자적 UPDATE**가 현실적 최선.

> ## 🔗 참고 자료
> - 김영한 『자바 ORM 표준 JPA 프로그래밍』 16장 (낙관적·비관적 락, `@Version`, `LockModeType`)
> - Hibernate User Guide — *Locking* / Vlad Mihalcea 블로그(Optimistic vs Pessimistic, Lost Update)

> ## 🌱 심화 키워드
> - **`@Version` / OptimisticLockException** — 버전 기반 충돌 감지
> - **LockModeType (OPTIMISTIC / OPTIMISTIC_FORCE_INCREMENT / PESSIMISTIC_READ / PESSIMISTIC_WRITE)**
> - **SELECT … FOR UPDATE / 행 락 / 데드락** — 비관적 락의 DB 동작
> - **Lost Update / Write Skew** — 격리수준과 갱신 이상현상
> - **원자적 UPDATE / 분산 락(Redis·Redisson)** — 단일 DB 락의 대안 (다중 서버)

> ## ❓ 남은 질문
> 1. (해결 — 2-1장) 낙관적 락은 **CAS**: 검사를 `WHERE version=?`에 넣어 원자화 + 행 쓰기 락으로 순차화. → 후속: **재시도를 어디서 어떻게** 구현하나(`@Retryable`/직접 루프)? 재시도 횟수·백오프는?
>    → **답:** 서비스 계층에서 `OptimisticLockException`을 잡아 재시도한다 — 스프링이면 `@Retryable`(예외·maxAttempts·backoff 지정)이 간편, 직접 for 루프도 가능. 보통 3~5회 + 지수 백오프(+지터)로, 짧은 트랜잭션이라 재실행 비용이 작다.
> 2. `OPTIMISTIC_FORCE_INCREMENT`는 언제 필요한가? (연관 엔티티만 바뀌어도 부모 버전을 올려야 할 때)
>    → **답:** 부모 필드는 안 바뀌고 **연관 자식만 바뀌었는데도** 부모의 논리적 상태가 바뀐 것으로 봐야 할 때, 부모 `@Version`을 강제로 올려 다른 트랜잭션의 낡은 부모 갱신을 충돌로 잡는다(집합체 일관성 보호).
> 3. 여러 서버(인스턴스)에서 같은 행을 다툰다면 DB 락만으로 충분한가, 아니면 분산 락이 필요한가? (→ [../distributed/distributed-lock-and-consensus.md] 연결)
>    → **답:** 경합 지점이 **DB의 한 행**이면 낙관적/비관적 DB 락이 여러 서버에서도 그대로 유효하다(락 주체가 DB라 인스턴스 수와 무관). 분산 락은 DB 밖 자원(외부 API·파일·중복 실행 방지)을 여러 서버가 다툴 때 필요하다.
