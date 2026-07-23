# 트랜잭션 & 격리수준 (Transaction & Isolation)

> **한 줄 정의:** 트랜잭션은 *"쪼갤 수 없는 하나의 논리적 작업 단위"*, 격리수준은 *"동시에 도는 트랜잭션끼리 서로를 얼마나 못 보게 막을지의 강도 다이얼"*이다.

> 관련 문서:
> - [../distributed/distributed-lock-and-consensus.md](../distributed/distributed-lock-and-consensus.md) — 락이 단일 DB를 넘어 분산 환경으로 가면(분산 락·합의·CAP)
> - [../architecture/saga-pattern.md](../architecture/saga-pattern.md) — ACID로 못 묶는 분산 트랜잭션의 대안(보상 거래)
> - [../spring/spring-async-event-listener.md](../spring/spring-async-event-listener.md) — `@Transactional`과 이벤트 커밋 시점

---

## 1. 트랜잭션과 ACID — "무엇으로 보장되나"가 핵심

계좌 이체("A에서 빼고 B에 더하기")는 전부 되거나 전부 안 되어야 한다. ACID는 그 보장의 네 측면이고, 면접에선 **"어떤 메커니즘으로 보장되나"**를 묻는다.

| 글자 | 의미 | **구현 메커니즘 (면접 포인트)** |
|------|------|-------------------------------|
| **A**tomicity (원자성) | 전부 OR 전무 | **Undo Log** — 변경 전 값을 적어두고 실패 시 rollback |
| **C**onsistency (일관성) | 규칙이 안 깨짐 | 제약조건(PK/FK/NOT NULL) + **앱 로직**. *DB만의 책임 아님(공동 책임)* |
| **I**solation (격리성) | 동시 실행이 순차처럼 | **격리수준 + 락 + MVCC** |
| **D**urability (지속성) | 커밋되면 영구 | **Redo Log (WAL, Write-Ahead Log)** — 변경을 로그에 먼저 적고 commit, 죽어도 복구 |

- 원자성 = **언두 로그(되돌리기)**, 지속성 = **리두 로그/WAL(다시 적용해 복구)**. 이 한 줄이 깊이의 증거.
- "Consistency는 DB가 다 보장하나요?" → **아니요, 앱·제약조건의 공동 책임**이 정답.

---

## 2. 왜 격리수준이 필요한가 — 동시성 이상현상 3가지

완벽 격리(SERIALIZABLE)는 안전하지만 느리다. 그래서 "이 정도 이상현상은 감수하고 속도를 얻자"는 등급을 둔다. 막아야 할 현상 3개:

```
[Dirty Read]            커밋도 안 된 값을 읽음
 T1: UPDATE 잔액=0 (커밋 X) → T2: SELECT 잔액 → 0 읽음 → T1: ROLLBACK (T2는 헛것을 봄)

[Non-repeatable Read]   같은 '행'을 두 번 읽었는데 값이 다름
 T1: SELECT 잔액 → 100 → T2: UPDATE 잔액=50; COMMIT → T1: SELECT 잔액 → 50

[Phantom Read]          같은 조건 '범위'조회인데 행 '개수'가 달라짐
 T1: count WHERE age>20 → 5건 → T2: INSERT(age=30); COMMIT → T1: count → 6건
```

> 구분: **Non-repeatable = 기존 행의 *값* 변동**, **Phantom = 행의 *개수(범위)* 변동**. 이 둘 헷갈리면 티 난다.

---

## 3. 격리수준 4단계

각 수준이 위 3현상 중 무엇을 막는지가 전부다:

| 격리수준 | Dirty | Non-repeatable | Phantom |
|----------|:---:|:---:|:---:|
| **READ UNCOMMITTED** | 허용 | 허용 | 허용 |
| **READ COMMITTED** | 차단 | 허용 | 허용 |
| **REPEATABLE READ** | 차단 | 차단 | 허용* |
| **SERIALIZABLE** | 차단 | 차단 | 차단 |

- 위로 갈수록 **안전 ↑ / 동시성·성능 ↓** (트레이드오프 다이얼).
- `*` 표준상 RR은 Phantom 허용이지만, **MySQL InnoDB는 Next-Key Lock(갭 락)으로 Phantom까지 거의 막음** ← 가산점.

### DB별 기본값 (자주 물음)
- **MySQL(InnoDB): `REPEATABLE READ`**
- **PostgreSQL / Oracle: `READ COMMITTED`**
- 왜 다른가 → MySQL은 복제(replication) 일관성 때문에 더 높게, 대부분 웹 서비스는 RC로 충분해서 PostgreSQL은 그쪽.

---

## 4. 구현 원리 — MVCC와 락

### MVCC (Multi-Version Concurrency Control)
- **읽기는 락을 안 잡는다.** 대신 데이터의 **여러 버전(스냅샷)**을 언두 로그로 유지.
- 트랜잭션은 "시작 시점 스냅샷"을 읽으므로, 남이 값을 바꿔도 내 버전을 계속 읽음 → **읽기/쓰기가 서로를 안 막아** 동시성↑. (RR의 "같은 값 반복 보장"이 이걸로 구현)

### 락 — 쓰기 충돌 제어
- **비관적 락(Pessimistic):** "충돌 잦다" 가정 → 미리 잠금. `SELECT ... FOR UPDATE`(배타락).
- **낙관적 락(Optimistic):** "충돌 드물다" 가정 → 안 잠그고 **버전 컬럼**으로 커밋 시 검증, 충돌 시 재시도. (JPA `@Version`)

```java
// 비관적 — 충돌 잦고 손실이 치명적일 때
@Lock(LockModeType.PESSIMISTIC_WRITE)
@Query("select i from Item i where i.id = :id")
Item findByIdForUpdate(@Param("id") Long id);    // SELECT ... FOR UPDATE

// 낙관적 — 충돌 드물 때 (평상시 가벼움)
@Entity
class Item {
    @Version private Long version;               // 다르면 OptimisticLockException
}
```

### 락의 3계층 (어디서 동시성이 깨지나)
| 계층 | 예시 | scale-out(앱 서버 N대)에서 |
|------|------|--------------------------|
| ① 애플리케이션 락 | `synchronized` | ❌ 깨짐 (JVM 안에서만 유효) |
| ② **DB 락** | `FOR UPDATE`, `@Version` | ✅ **동작** (DB가 공유 지점=심판) |
| ③ 분산 락 | Redis, ZooKeeper | ✅ (별도 인프라, → 분산 노트) |

> **핵심:** scale-out에서 깨지는 건 ①번뿐. **DB 락은 DB가 단일 진실원이라 앱 서버가 몇 대든 동작**한다. "scale-out이니 무조건 Redis"는 과한 답.

---

## 5. 실전 — 재고 동시성 (면접 단골)

```java
@Transactional
public void order(Long itemId) {
    Item item = repo.findById(itemId);   // 재고 읽기
    if (item.getStock() < 1) throw new SoldOutException();
    item.setStock(item.getStock() - 1);  // 차감
}
```

- 락이 없으면 두 요청이 **같은 재고를 읽고 → 같은 값으로 차감 → 한 번의 차감이 증발(Lost Update)**, 재고가 음수까지.
- **선착순 100개에 수천 명**(충돌 극심)일 때:
  - **낙관적 락** → 실패→재시도→또 실패 = **재시도 지옥**, DB·앱 둘 다 폭발. ❌
  - **비관적 락** → 한 줄로 직렬화 → 각 요청이 **커넥션을 오래 점유 → 커넥션 풀 고갈 → 무관한 API까지 마비**, 최악엔 데드락.
- **진짜 정답 (둘 다 한계라서):**
  1. **원자적 단일 UPDATE** — `UPDATE item SET stock = stock - 1 WHERE id = ? AND stock > 0;` → `affected rows = 0`이면 매진. **read-check-write race 자체가 사라짐.**
  2. **Redis 선차감(`DECR`)** 후 주문은 큐로 비동기 반영.

> 선택 기준은 결국 **"충돌 빈도"** 하나: 잦으면 비관/원자적 UPDATE, 드물면 낙관.

---

## 6. 흔한 함정 (면접 단골)

- **`@Transactional` self-invocation:** AOP 프록시 기반이라 **같은 클래스 내부 호출은 트랜잭션이 안 걸림**.
- **`synchronized` + `@Transactional`:** 순서가 `락 획득 → 실행 → 락 해제 → (프록시)커밋`이라, **락이 풀린 뒤 커밋**되어 그 찰나에 다음 스레드가 옛 값을 읽음 → 동시성 안 지켜짐. → "락은 트랜잭션 바깥에서 감싸야 한다."
- **격리수준만 높이면 안전?** No. **데드락·락 대기·성능 저하**가 따라옴. "무조건 SERIALIZABLE"은 오답.
- **Lost Update:** RR이라도 락 없이 `read→수정→write`하면 서로 덮어씀.

---

## 🔗 참고 자료
- 『Real MySQL 8.0』 4~5장(트랜잭션과 잠금) — 한국 자바 백엔드 사실상 표준 교재
- 『데이터베이스 인터널스』 — WAL/MVCC 원리
- MySQL 공식: *InnoDB Locking and Transaction Model*
- PostgreSQL 공식: *Transaction Isolation*

## 🌱 심화 키워드
- **Next-Key Lock / Gap Lock** — InnoDB가 Phantom 막는 법
- **Lost Update** — 격리수준만으론 못 막는 갱신 손실
- **2PL (Two-Phase Locking)** — SERIALIZABLE의 이론적 토대
- **Snapshot Isolation / Write Skew** — MVCC의 한계
- **Connection Pool 고갈** — 비관적 락의 진짜 위험 (HikariCP `maximumPoolSize`)
- **Deadlock** — 락 순서와 교착 (`SHOW ENGINE INNODB STATUS`)

## ❓ 남은 질문 (이어서 팔 것)
1. 낙관적 락 충돌 시 재시도 전략을 사용자 경험과 어떻게 조화시키나? (지수 백오프 등)

   → **답:** 실패를 곧장 사용자에게 노출하지 말고 서버가 지수 백오프(+지터)로 몇 회 자동 재시도한 뒤, 그래도 실패하면 안내한다. 재고 차감처럼 짧은 트랜잭션일수록 재시도가 값싸 UX 영향이 작다.
2. InnoDB의 Next-Key Lock이 정확히 어떤 범위를 잠그나? (레코드 락 + 갭 락)

   → **답:** Next-Key Lock = **레코드 락 + 그 앞 간격(갭) 락**으로, 매칭 인덱스 레코드와 앞 갭까지 잠가 REPEATABLE READ에서 팬텀을 막는다. 유니크 인덱스 단건 등가조회면 갭 없이 레코드 락으로 축소된다.
3. 원자적 UPDATE 방식의 한계는? (재고 외 복잡한 검증이 필요할 때)

   → **답:** `SET stock=stock-1 WHERE stock>0`처럼 한 문장으로 표현되는 단순 검증엔 완벽하지만, 여러 행·여러 테이블에 걸친 복합 조건이나 애플리케이션 로직 검증이 필요하면 한 UPDATE에 못 담아 결국 낙관적/비관적 락이 필요하다.
