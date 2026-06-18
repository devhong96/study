# 영속성 컨텍스트 & N+1 & OSIV

> **한 줄 정의:** 영속성 컨텍스트는 *"트랜잭션 범위의 엔티티 보관소(1차 캐시·변경 감지·쓰기 지연)"*, N+1은 *"지연로딩이 N번 추가 쿼리를 내는 문제"*, OSIV는 *"그 컨텍스트를 뷰까지 열어둘지의 트레이드오프"*다.

> 관련 문서:
> - [em-threadlocal-transaction.md](em-threadlocal-transaction.md) — 이 영속성 컨텍스트가 프록시 EM·ThreadLocal로 스레드에 묶이는 런타임 원리
> - [second-level-cache.md](second-level-cache.md) — 1차 캐시가 TX를 못 넘는 한계를 메우는 앱 레벨 2차 캐시
> - [../spring/transactional-deep-dive.md](../spring/transactional-deep-dive.md) — ThreadLocal에 묶이는 그 EntityManager가 곧 영속성 컨텍스트
> - [../database/transaction-and-isolation.md](../database/transaction-and-isolation.md) — 커넥션 풀 고갈(OSIV에서 또 등장)

---

## 1. 영속성 컨텍스트 — JPA의 심장

`@Transactional` 시작 시 스레드에 묶이는 `EntityManager`가 관리하는 엔티티 보관소.

| 기능 | 설명 |
|------|------|
| **1차 캐시** | `id`로 보관. 같은 TX 재조회 시 **DB 안 감** + **동일성(`==`) 보장** |
| **변경 감지(dirty checking)** | 스냅샷을 떠두고 flush 때 비교 → 변경분 자동 UPDATE (`readOnly`가 끄는 그 스냅샷) |
| **쓰기 지연(write-behind)** | INSERT/UPDATE를 모았다가 **flush 때 한꺼번에** 전송 |
| **flush** | 변경을 DB에 반영. **flush ≠ commit** (flush=SQL 전송, commit=확정) |

> 생명주기: 비영속(new) → `persist` → **영속(managed)** → `detach`/TX 종료 → **준영속(detached)**. 준영속 + 지연로딩 = `LazyInitializationException`.

---

## 2. N+1 문제 (면접 최다)

팀 10개 조회 후 각 팀의 멤버 출력:
```java
List<Team> teams = em.createQuery("select t from Team t", Team.class).getResultList(); // 쿼리 1
for (Team t : teams) t.getMembers().size();   // 팀마다 SELECT … WHERE team_id=? → N번
// 총 1 + N 💥
```
**원인:** 부모 N개를 가져온 뒤 각 연관을 **개별 지연로딩**.

### ⚠️ 최대 오해: "EAGER로 바꾸면 해결" → 틀림
JPQL `select t from Team`은 SQL로 그대로 번역돼 **팀만 먼저** 가져오고, EAGER 연관을 채우러 **팀마다 추가 쿼리** → N+1 그대로. (오히려 예측 불가라 더 위험) → **전부 LAZY 깔고 필요할 때 fetch join**이 정석.

### 해결책
| 방법 | 동작 | 비고 |
|------|------|------|
| **fetch join** | 조인으로 한 방 | 1순위. `join fetch t.members` |
| **@EntityGraph** | fetch join을 어노테이션으로 | Spring Data 궁합 |
| **batch size** | N번을 `IN (?,?,…)` 한 번 → 1+1 | 컬렉션에 현실적. `default_batch_fetch_size` |
| **DTO 직접 조회** | 필요한 컬럼만 projection | 조회 전용 최적 |

### fetch join의 함정 (★)
- **컬렉션 fetch join + 페이징 = 위험.** 전부 메모리로 가져와 **메모리 페이징**(`applying in memory` 경고 → OOM). 일대다 조인은 row가 뻥튀기돼 DB 페이징 불가.
- **컬렉션 fetch join 2개 = `MultipleBagFetchException`**(카테시안 곱). `Set`이면 예외는 피해도 곱은 남음.
- **실전 패턴:** *ToOne은 fetch join, ToMany(컬렉션)는 batch size*.

---

## 3. OSIV (Open Session In View)

`spring.jpa.open-in-view` 기본 `true`.

```
[ON]  영속성 컨텍스트+커넥션을 HTTP 응답 끝(뷰)까지 유지
      → 컨트롤러/뷰에서도 지연로딩 OK (편함)  / 단 커넥션을 요청 내내 점유 😱
[OFF] 트랜잭션(서비스) 범위만 유지 → 커넥션 효율 ↑
      → TX 밖 지연로딩 시 LazyInitializationException → 서비스에서 fetch 끝내야
```
- **수명 정밀하게:** ON이면 컨텍스트가 **요청 시작 ~ 응답 끝(뷰 렌더링)**까지. ("DB 연결 시점까지"가 아니라 *응답 끝까지*가 OSIV의 뜻 — Open Session In **View**.)
- **ON 위험(메커니즘):** 커넥션은 트랜잭션 시작 때 잡히는데, **트랜잭션이 끝나도(서비스 반환) 반납하지 않고 응답 끝까지 쥔다** — 컨트롤러/뷰 지연로딩을 위해. → 컨트롤러에서 외부 API·느린 뷰 같은 게 끼면 **커넥션을 놀리면서도 점유** → 트래픽 몰리면 **커넥션 풀 고갈**(비관적 락·REQUIRES_NEW와 같은 병: *자원을 필요 이상으로 오래 점유*).
- **OFF의 개발자 책임 = "범위 설정"이 아니라 "뷰 나가기 전에 지연로딩을 다 끝내 두기".** 구체적으로 **서비스 트랜잭션 안에서 fetch join/`@EntityGraph`로 로딩 후 DTO로 변환해 반환**. 거기선 컨텍스트가 살아있어 지연로딩이 되고, 컨트롤러로 나갈 땐 값만 든 DTO라 준영속과 무관.
- **한 해법이 세 문제를 동시에 푼다(★):** "엔티티는 영속성 계층, DTO는 표현 계층" 원칙 → ① OSIV OFF의 `LazyInitializationException` 방지 ② 직렬화 중 숨은 N+1·무한순환 방지(4-1) ③ API 스펙의 DB 강결합 방지.

> `LazyInitializationException`: TX 종료로 준영속이 된 엔티티의 지연로딩 프록시를 건드리면 컨텍스트가 없어 초기화 실패.

---

## 4. 실전 함정

### 4-1. 엔티티를 그대로 API 응답으로 주지 마라
1. **지연로딩 직렬화 폭발:** Jackson이 모든 필드에 접근 → LAZY 연관까지 건드려 OSIV OFF면 `LazyInitializationException`, ON이면 **숨은 N+1**이 직렬화 중 줄줄이.
2. **양방향 무한 순환:** `Team↔Member` 직렬화가 무한 루프 → StackOverflow (`@JsonIgnore`는 표현 문제를 엔티티에 침범시키는 냄새).
3. **API 스펙이 DB에 강결합:** 컬럼 추가가 응답에 새어나가고, `password` 등 **민감 필드 노출** 위험.
4. **Hibernate 프록시 직렬화 에러.**

→ **정답: DTO로 변환해 응답.** 엔티티=영속성 계층, DTO=표현 계층. 변환을 서비스(TX 안)에서 끝내면 지연로딩 문제도 동시 해결.

### 4-2. 대량 INSERT(예: 5만 건)가 느린 이유와 해결
- **왜:** 기본은 INSERT를 **한 건씩 전송**(왕복 5만 번). JDBC batch 미설정이면 안 묶임.
- **해결:** `hibernate.jdbc.batch_size`(500~1000) + `order_inserts/order_updates: true`.
- **🔥 함정 — `IDENTITY`(MySQL AUTO_INCREMENT)는 batch insert 불가:** INSERT를 실행해야 PK를 알 수 있어 쓰기 지연/배치가 무력화. → `SEQUENCE`/`TABLE` + `allocationSize`로 PK 선확보해야 배치 가능. **MySQL은 시퀀스가 없어** 보통 IDENTITY라 골치 → 대안: **JdbcTemplate bulk insert**, 멀티 row `INSERT … VALUES (…),(…)`, 드라이버 `rewriteBatchedStatements=true`.
- **메모리:** 5만 건이 1차 캐시·스냅샷에 쌓이면 OOM/GC → **주기적 `flush()` + `clear()`**.

---

> ## 📌 핵심 요약
> 영속성 컨텍스트 = TX 범위 엔티티 보관소(1차 캐시·변경 감지·쓰기 지연). **N+1**은 지연로딩의 N번 추가 쿼리이며 **EAGER는 해결책이 아니다** → fetch join(ToOne)+batch size(ToMany), 컬렉션 페이징 함정 주의. **OSIV**는 편의 vs 커넥션 점유 트레이드오프, 대규모는 OFF + 명시적 페치.

> ## 🔗 참고 자료
> - 김영한 『자바 ORM 표준 JPA 프로그래밍』 + 인프런 "JPA 활용편 2"(N+1·OSIV)
> - Hibernate User Guide: *Fetching* / Vlad Mihalcea 블로그(N+1·batch·페이징)

> ## 🌱 심화 키워드
> - **LazyInitializationException / Hibernate Proxy** — 준영속+지연로딩, `Hibernate.initialize()`
> - **@BatchSize / hibernate.default_batch_fetch_size** — N+1을 IN 절로
> - **MultipleBagFetchException / Bag(List) vs Set / 카테시안 곱**
> - **쓰기 지연 + JDBC Batch(hibernate.jdbc.batch_size)** — 대량 INSERT
> - **IDENTITY 전략은 batch insert 불가** — 식별자 전략과 성능
> - **DTO Projection / Querydsl**, **2차 캐시(Second-Level Cache)**
> - **OSIV** — open-in-view 트레이드오프
