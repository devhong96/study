# SQL JOIN — 논리적 종류와 fan-out (곱 → 필터로 이해하기)

> **한 줄 정의:** 모든 JOIN은 개념적으로 *"두 테이블의 **카티션 곱(CROSS)**을 만든 뒤 조건으로 **필터**한 것"*이다. 이 "곱 → 필터" 모델 하나로 INNER·OUTER·fan-out·ON vs WHERE가 전부 설명된다.
>
> *(중간 정리 초안 — 논리 층까지. 물리 조인 알고리즘(Nested Loop/Hash/Merge)은 다음 세션 예정.)*

> 관련 문서:
>
> - [db-index.md](db-index.md) — 조인 조건 컬럼에 인덱스가 있어야 조인이 빠르다 (물리 알고리즘과 직결)
> - [transaction-and-isolation.md](transaction-and-isolation.md) — 함께 DB 면접 핵심
> - [../jpa/persistence-context-and-n-plus-one.md](../jpa/persistence-context-and-n-plus-one.md) — fan-out은 JPA 컬렉션 fetch join의 `MultipleBagFetchException`·중복 엔티티 문제의 뿌리

---

## 1. 뿌리 — CROSS JOIN은 "곱"이다 (합집합 아님)

두 테이블 `member(3행)`, `orders(3행)`를 CROSS JOIN(`FROM member, orders`)하면 **3 × 3 = 9행**. 한쪽의 **각 행**을 다른 쪽 **모든 행**과 짝짓는 **카티션 곱**이다.

| 연산                      | 하는 일                                         | 결과                                  |
| ------------------------- | ----------------------------------------------- | ------------------------------------- |
| **UNION (합집합)**  | 두 결과를**세로로 쌓음** (같은 컬럼 구조) | 행이 더해짐 (3+3=6)                   |
| **CROSS JOIN (곱)** | 모든 행 × 모든 행                              | 옆으로 컬럼 붙고 행이 곱해짐 (3×3=9) |

> ⚠️ **흔한 오개념:** "CROSS = 합집합"은 틀림. 합집합은 `{a,b} ∪ {b,c}`처럼 **더하기**, 카티션 곱은 `{a,b} × {c,d}`처럼 **곱하기**. 그래서 6이 아니라 9.

---

## 2. INNER JOIN = 곱 → 필터

`INNER JOIN ... ON member.id = orders.member_id`는 위 9행 카티션 곱에서 **ON 조건을 만족하는 행만 남긴 것**.

```
CROSS(9행)  --  ON m.id = o.member_id 필터  -->  INNER(3행)
```

> **정의:** INNER JOIN = 두 테이블의 카티션 곱에서 ON 조건을 만족하는 행만 남긴 것.

- "교집합" 비유는 벤다이어그램용 직관일 뿐 **반쪽짜리**다. 결과 컬럼은 양쪽을 **가로로** 붙인 것이고, 1:N이면 결과 행이 **어느 원본 테이블보다 많아질 수** 있다(순수 교집합은 원소가 늘 수 없음). → 이게 곱→필터의 흔적.

---

## 3. fan-out — 1:N 조인의 행 증폭과 집계 오염 ⭐

### 3.1 무엇

한 행이 여러 행과 매칭되는 **1:N 조인**에서 결과 행이 불어나는 현상. 회원 1명 주문 100건 → INNER 결과 100행.

### 3.2 왜 위험 — 집계가 뻥튀기된다

**서로 관계없는 1:N 가지 두 개**를 한 쿼리에서 조인하면 두 자식 집합이 서로 곱해진다.

```
        member(김철수)
        /            \
   orders(2건)    addresses(3건)   ← 둘은 서로 무관 (각각 member에만 매달림)
   5000, 3000     집/회사/부모님댁
```

```sql
SELECT SUM(o.amount)
FROM member m
JOIN orders    o ON m.id = o.member_id
JOIN addresses a ON m.id = a.member_id   -- 주문·배송지 둘 다 member에 1:N
WHERE m.id = 1;
```

주문 2건이 배송지 3건과 무차별로 곱해져 **6행** → 각 주문 금액이 3번씩 더해짐:

`SUM = 5000×3 + 3000×3 = 24000` (진짜 합 8000의 **×3**)

> 📌 **규칙:** 1:N 가지 두 개를 한 쿼리에서 집계하면, 한쪽 집계값은 **반대쪽 가지의 행 수만큼** 곱해진다. (배송지 5건이면 ×5 = 40000)

> ⚠️ **오해 주의 — "8000인데 왜 40000?"**
> 배송지가 5건이면 각 주문 행이 5번 복제돼 `SUM(o.amount) = 8000 × 5 = 40000`. 진짜 합 8000으로 **착각하기 딱 좋다**.
> - **배송지엔 amount가 없다.** 배송지는 금액에 기여하는 게 아니라 **주문 행을 복제하는 배수**로만 작용한다.
> - **뻥튀기 배수는 값 분포와 무관.** 주문이 `5000+3000`이든 `1+7999`든 합이 8000이면 결과는 똑같이 40000 (`1×5 + 7999×5 = 8000×5`). 개별 금액이 아니라 **(진짜 합) × (반대 가지 행 수)**만 결정한다.
> - 그래서 더 위험하다 — 정확히 N배로 **균일하게** 틀려 "그럴듯한 큰 수"로 보이고, 로그로는 눈치채기 어렵다.
> - **8000을 정확히 얻으려면** → 3.3의 pre-aggregation (스칼라 서브쿼리 / 파생 테이블).

### 3.3 어떻게 막나 — 조인/필터가 아니라 "집계 시점"

문제는 **곱해진 뒤에 집계**해서 생긴다. → **곱하기 전에 각 가지를 회원당 1행으로 미리 접는다(pre-aggregation).**

```sql
-- ① 스칼라 서브쿼리 (독립 실행 → 배송지와 안 곱해짐)
SELECT m.name,
       (SELECT SUM(amount) FROM orders WHERE member_id = m.id) AS total
FROM member m;

-- ② 파생 테이블 (미리 GROUP BY로 1행 접기 → 1×1 조인)
SELECT m.name, o.total, a.cnt
FROM member m
JOIN (SELECT member_id, SUM(amount) total FROM orders    GROUP BY member_id) o ON o.member_id = m.id
JOIN (SELECT member_id, COUNT(*)   cnt   FROM addresses GROUP BY member_id) a ON a.member_id = m.id;
```

> ❌ **"조인 방식/필터로 막는다"는 오답.** 배송지를 어떻게 조인·필터하든 1건이라도 남으면 주문 집계는 그만큼 여전히 오염된다. 조인 방식이 아니라 **집계하는 시점**의 문제.

---

## 4. OUTER JOIN — 안 맞는 행을 NULL로 살린다

INNER는 매칭 안 된 행을 **버린다**(주문 없는 박민수 탈락). OUTER는 살린다.

```
member LEFT JOIN orders ON m.id = o.member_id
| m.name | o.id | amount |
| 김철수 | 10   | 5000   |
| 김철수 | 11   | 3000   |
| 이영희 | 12   | 8000   |
| 박민수 | NULL | NULL   |  ← 매칭 없어도 왼쪽은 전부 남고, 오른쪽은 NULL
```

> **정의:** LEFT JOIN = INNER 결과 + **왼쪽 테이블에서 매칭 안 된 행 전부**(오른쪽은 NULL). "**왼쪽은 무조건 전부 나온다**"가 보장.
>
> - **핵심 주의:** 왼쪽은 조건으로 필터되지 않는다. ON은 "오른쪽에서 뭘 붙일지"만 결정.
> - RIGHT = 방향만 반대, FULL = 양쪽 다 보존. (CROSS는 조건 없는 전체 곱.)

---

## 5. 논리적 실행 순서 & ON vs WHERE

### 5.1 작성 순서 ≠ 처리 순서

SQL은 `SELECT`부터 쓰지만 **처리는 `FROM`부터**. (이건 옵티마이저가 실제 물리 실행을 재배치하기 전의 **의미론적 순서**다.)

| 순서 | 절                              | 하는 일                                                           |
| ---- | ------------------------------- | ----------------------------------------------------------------- |
| 1    | **FROM / JOIN**           | 테이블 결합(곱)                                                   |
| 2    | **ON**                    | 조인 조건 평가 →**매칭 + outer join의 NULL 채움이 여기서** |
| 3    | **WHERE**                 | 완성된 행 필터                                                    |
| 4    | GROUP BY                        | 그룹핑                                                            |
| 5    | HAVING                          | 그룹 필터                                                         |
| 6    | **SELECT**                | 컬럼·별칭 생성                                                   |
| 7    | DISTINCT / 8 ORDER BY / 9 LIMIT |                                                                   |

- 부산물: **WHERE에서 SELECT 별칭 못 씀**(3 < 6), **ORDER BY에선 됨**(8 > 6).

### 5.2 ON vs WHERE — outer join에서 갈린다

```sql
-- WHERE 버전: 조인 후 필터 → 박민수의 NULL 행 제거 → LEFT가 INNER로 변질
LEFT JOIN orders o ON m.id = o.member_id
WHERE o.amount >= 3000        -- NULL >= 3000 = UNKNOWN → 컷

-- ON 버전: 매칭 단계에서 필터 → 왼쪽(박민수) 보존, 안 맞으면 NULL
LEFT JOIN orders o ON m.id = o.member_id AND o.amount >= 3000
```

|                    | ON                        | WHERE                 |
| ------------------ | ------------------------- | --------------------- |
| 시점               | 조인 매칭 중(2)           | 조인 후(3)            |
| 역할               | 어떤 오른쪽 행을 붙일지   | 완성된 결과 필터      |
| outer join 왼쪽 행 | **보존**(NULL 가능) | NULL 행**제거** |

> 실무 감각: outer join에서 **오른쪽 테이블 조건은 ON에**, **왼쪽(보존할) 테이블 조건은 WHERE에**. (INNER에선 ON/WHERE가 사실상 동일 — 차이는 NULL 행이 있는 OUTER에서만 의미.)
> `NULL` 비교가 `UNKNOWN`이 되는 건 SQL **3값 논리**(TRUE/FALSE/UNKNOWN) 때문. WHERE는 TRUE만 통과시킴.

---

> ## 📌 핵심 요약
>
> 모든 조인은 **곱(CROSS) → 필터(ON)**. INNER는 매칭만 남기고, OUTER는 안 맞는 쪽을 **NULL로 살린다**. 1:N 가지 두 개를 한 쿼리에서 집계하면 **fan-out**으로 집계값이 반대 가지 행 수만큼 뻥튀기 → **조인 전에 미리 집계(pre-aggregation)**로 막는다. ON은 조인 시점(2)·WHERE는 조인 후(3)라, outer join에서 오른쪽 조건을 WHERE에 두면 NULL 행이 제거돼 INNER로 변질된다.

> ## 🔗 참고 자료
>
> - 『SQL 첫걸음』/『Real MySQL 8.0』 — 조인·실행계획 (한국어 표준)
> - PostgreSQL 공식 문서 — *Table Expressions: Joined Tables* (ON/USING/NATURAL, outer join 정의)
> - Use The Index, Luke! — 조인과 인덱스 (물리 알고리즘으로 연결)

> ## 🌱 심화 키워드
>
> - **Nested Loop / Hash / Sort-Merge Join** — 논리 조인을 실제로 수행하는 물리 알고리즘 (다음 세션 핵심)
> - **pre-aggregation / derived table / lateral join** — fan-out 없이 다중 1:N 집계
> - **3값 논리(three-valued logic) / NULL 비교** — `NULL = NULL`도 UNKNOWN
> - **MultipleBagFetchException** — JPA에서 컬렉션 두 개 fetch join = fan-out 폭발
> - **SEMI JOIN / ANTI JOIN (EXISTS / NOT EXISTS)** — "곱하지 않고" 존재만 확인하는 조인

> ## ❓ 남은 질문
>
> 1. **물리 알고리즘 (다음 세션):** Nested Loop vs Hash vs Sort-Merge — 옵티마이저는 무엇을 보고 고르나? 각 알고리즘에 인덱스는 어떻게 작용하나?
> 2. RIGHT/FULL OUTER JOIN 실제 사용 사례, MySQL이 FULL을 지원 안 하는데 어떻게 흉내내나(`UNION`)?
> 3. `EXISTS`(세미조인) vs `IN` vs `JOIN` — 언제 무엇이 빠른가?
> 4. fan-out을 `COUNT(DISTINCT ...)`로 우회하는 건 언제 되고 언제 안 되나(SUM엔 왜 안 통하나)?
