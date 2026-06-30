# DB View (뷰 · 구체화 뷰)

> **한 줄 정의:** 일반 View는 *"이름이 붙은 저장된 SELECT 문(가상 테이블)"*일 뿐, **성능 최적화가 아니라 추상화·보안·편의성**을 위한 기능이다. 진짜 최적화는 결과를 디스크에 저장하는 **Materialized View(구체화 뷰)**가 담당한다.


---

## 0. 흔한 오해부터 교정

| 오해 | 사실 |
|------|------|
| "View는 복잡한 조회를 **최적화**하는 기법이다" | ❌ 일반 View는 **저장된 쿼리일 뿐**. JOIN을 매번 다시 실행해서 속도는 직접 쿼리와 **동일**하다. |
| "특정 필드만 뷰에 넣으면 나머지 필드가 바뀌어도 문제없다" | △ 나머지 컬럼의 **값(데이터)**이 바뀌는 건 무관. 하지만 참조 컬럼이 **삭제·이름변경·타입변경** 되면 뷰는 **깨진다.** 뷰는 원본 테이블 구조에 **강하게 종속**된다. |

---

## 1. 일반 View = "저장된 SELECT 문"

View는 실제 데이터를 담지 않는 **가상 테이블**이다. 조회할 때마다 내부적으로 원본 쿼리로 **펼쳐서(rewrite)** 실행한다.

```sql
-- 뷰 생성
CREATE VIEW order_summary AS
SELECT o.id, u.name, o.total
FROM orders o
JOIN users u ON o.user_id = u.id;

-- 뷰 조회
SELECT * FROM order_summary WHERE total > 1000;
```

위 조회는 DB 내부에서 이렇게 실행된다:

```sql
SELECT * FROM (
  SELECT o.id, u.name, o.total
  FROM orders o JOIN users u ON o.user_id = u.id
) AS v
WHERE total > 1000;
```

→ **JOIN은 매번 다시 돈다. 빨라지지 않는다.**

---

## 2. 그럼 View는 왜 쓰나 (진짜 목적)

| 목적 | 설명 |
|------|------|
| **복잡성 은닉** | 복잡한 JOIN/서브쿼리를 이름 하나로 추상화 → 재사용성 ↑ |
| **일관성** | 동일한 조회 로직을 여러 곳에 복붙하지 않고 한 곳에서 관리 |
| **보안/권한** | 일부 컬럼·행만 노출. 민감 컬럼(주민번호 등)을 뷰에서 빼면 사용자는 접근 불가 |
| **하위 호환** | 테이블 구조가 바뀌어도 뷰가 옛 인터페이스를 유지 |

> View의 본질 = **성능이 아니라 "추상화 / 보안 / 편의성"**.

---

## 3. 진짜 최적화: Materialized View (구체화 뷰)

쿼리 결과를 **실제로 디스크에 저장**해 두고, 조회 시 계산 없이 바로 읽는다.

| 구분 | 일반 View | Materialized View |
|------|-----------|-------------------|
| 데이터 저장 | ❌ 매번 재실행 | ✅ 결과를 디스크에 저장 |
| 조회 속도 | 원본 쿼리와 동일 | **빠름** (이미 계산된 결과) |
| 최신성 | 항상 최신 | **REFRESH 해야 갱신** (그 전엔 옛 데이터) |
| 지원 DB | 거의 모든 RDBMS | PostgreSQL, Oracle 등 (**MySQL은 미지원**) |

```sql
-- PostgreSQL 예시
CREATE MATERIALIZED VIEW order_summary_mv AS
SELECT o.id, u.name, o.total
FROM orders o JOIN users u ON o.user_id = u.id;

REFRESH MATERIALIZED VIEW order_summary_mv;  -- 수동 갱신 필요
```

**언제?** 무거운 집계(통계·대시보드)를 자주 조회하면서 **실시간성은 덜 중요**할 때.
**트레이드오프:** REFRESH 전까지는 **오래된 데이터**를 본다.

---

## 3-1. 언제 저장되고 언제 최신화되나 (REFRESH 타이밍)

> **핵심:** Materialized View는 **자동 최신화되지 않는다.** 누군가 **REFRESH를 실행한 그 순간에만** 갱신된다. 즉 **저장 시점 = CREATE 또는 REFRESH를 호출한 순간**의 스냅샷.

```
10:00  CREATE MATERIALIZED VIEW mv ...   → 이 순간 결과 계산해서 저장 (스냅샷)
10:05  원본 테이블에 INSERT 100건         → mv는 모름. 여전히 10:00 데이터
10:30  SELECT * FROM mv                   → 10:00 시점 데이터 반환 (stale)
10:40  REFRESH MATERIALIZED VIEW mv       → 이 순간 다시 계산해서 덮어씀 (최신화!)
10:41  SELECT * FROM mv                   → 이제 최신 데이터
```

그 사이 원본이 아무리 바뀌어도 MV는 모른다. 그래서 "오래된 데이터(stale)"라고 부른다.

### REFRESH는 누가/언제 호출하나 — 자동이 아니므로 설계해야 한다

| 방식 | 어떻게 | 예 |
|------|--------|-----|
| **수동** | 필요할 때 직접 실행 | `REFRESH MATERIALIZED VIEW mv;` |
| **스케줄링** | 크론/스케줄러로 주기 실행 | "매일 새벽 3시", "10분마다" |
| **트리거/온디맨드** | 특정 이벤트 후 실행 | 배치 작업이 끝나면 REFRESH 호출 |

```sql
-- PostgreSQL + pg_cron: 매시 정각마다 갱신
SELECT cron.schedule('0 * * * *', 'REFRESH MATERIALIZED VIEW mv');
```

### 갱신 중 조회 — CONCURRENTLY

```sql
REFRESH MATERIALIZED VIEW mv;              -- 갱신 동안 MV에 락 → 조회 막힘
REFRESH MATERIALIZED VIEW CONCURRENTLY mv; -- 갱신 중에도 조회 가능 (UNIQUE 인덱스 필요, 더 느림)
```

### 갱신 주기의 트레이드오프 (최신성 vs 비용)

- 주기를 **짧게** → 최신에 가깝지만 REFRESH 비용(무거운 JOIN 재계산)이 자주 발생
- 주기를 **길게** → 싸지만 데이터가 더 오래됨

→ 그래서 MV는 **"몇 분~몇 시간 옛 데이터여도 OK"**인 통계·대시보드·리포트에 쓴다. 실시간 정합성이 필요한 곳(잔액·재고)엔 부적합.

> **자동 갱신 옵션도 있다(주의):** Oracle의 `ON COMMIT` refresh, SQL Server의 *Indexed View*(항상 자동 동기화)는 원본이 바뀌면 알아서 갱신된다. 다만 **쓰기 성능을 깎아먹기 때문에** 기본은 수동/스케줄 방식이다.

---

## 4. 심화 포인트 (면접 단골)

### 4-1. Updatable View (갱신 가능 뷰)
- 단순 뷰(단일 테이블, 집계·DISTINCT·GROUP BY 없음)는 INSERT/UPDATE/DELETE가 **원본 테이블로 전파**될 수 있다.
- JOIN·집계·`GROUP BY`·`DISTINCT`가 들어간 복잡한 뷰는 일반적으로 **갱신 불가**(어느 원본 행을 바꿀지 모호하기 때문).
- `WITH CHECK OPTION` — 뷰 조건을 벗어나는 행이 INSERT/UPDATE 되는 것을 막는다.

### 4-2. View와 인덱스
- 일반 View 자체에는 인덱스를 못 건다(데이터가 없으니까). 성능은 **원본 테이블의 인덱스**가 결정한다
- Materialized View는 실제 데이터가 있으므로 **인덱스를 걸 수 있다**.
- (SQL Server의 *Indexed View*, Oracle의 *Materialized View*가 사실상 같은 개념.)

---

## 한 줄 요약

- **일반 View** = 저장된 쿼리. 최적화 ❌, 추상화·보안·편의성 ⭕
- **Materialized View** = 결과를 실제 저장. 최적화 ⭕, 대신 REFRESH(갱신) 필요
- View는 원본 테이블 구조에 **강하게 종속**된다.
