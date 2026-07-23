# JPA(ORM) vs MyBatis(SQL Mapper) — 왜/언제 무엇을

> **한 줄 정의:** 둘 다 "객체 ↔ RDB" 사이를 잇는 영속성 프레임워크지만 방향이 반대다 — **MyBatis는 *SQL Mapper*** (개발자가 SQL을 직접 쓰고 그 *결과*를 객체에 매핑), **JPA는 *ORM 표준 명세*** (객체 매핑을 선언하면 *SQL을 프레임워크가 생성*). 갈림길은 **"SQL을 내가 쥐느냐(MyBatis) vs 객체를 쥐고 SQL을 위임하느냐(JPA)"**. 우열이 아니라 **도메인 복잡도 vs 쿼리 복잡도**의 선택이고, 실무에선 **혼용**도 정당하다.

> 관련 문서:
> - [persistence-context-and-n-plus-one.md](persistence-context-and-n-plus-one.md) — JPA의 핵심 무기(영속성 컨텍스트)이자 최대 함정(N+1). 이 문서의 3·5장이 여기에 뿌리를 둠
> - [optimistic-pessimistic-lock.md](optimistic-pessimistic-lock.md) — `@Version` 낙관적 락은 JPA가 자동으로 얹어주는 기능(MyBatis는 수동)
> - [../database/transaction-and-isolation.md](../database/transaction-and-isolation.md) — 둘 다 결국 JDBC·트랜잭션 위에서 도는 얇은/두꺼운 껍질

---

## 1. 정체부터 — 명세 vs 라이브러리, ORM vs SQL Mapper

| | **JPA** | **MyBatis** |
|--|--|--|
| 무엇인가 | **표준 명세**(Jakarta Persistence, 옛 Java Persistence API) | **라이브러리**(SQL Mapper 프레임워크) |
| 구현체 | Hibernate(사실상 표준)·EclipseLink·OpenJPA | MyBatis 자체 (iBATIS의 후신) |
| 분류 | **ORM**(Object-Relational Mapping) | **SQL Mapper** (= half-ORM / 결과 매퍼) |
| Spring에서 | **Spring Data JPA**(JPA 위 추상화) | **MyBatis-Spring**(연동 모듈) |

- **JPA는 인터페이스(규격)일 뿐 실행 코드가 아니다.** 실제 동작은 Hibernate 같은 구현체가 한다. "JPA를 쓴다" ≈ 대개 "Hibernate를 JPA 표준 API로 쓴다".
- **MyBatis는 SQL을 대신 짜주지 않는다.** SQL은 100% 개발자가 작성하고, MyBatis는 ①파라미터 바인딩 ②`ResultSet` → 객체 매핑 ③동적 SQL 조립을 대신한다. **즉 "SQL을 없애는 게 아니라 SQL 다루는 반복을 없애는" 도구.**
- JPA는 그보다 한 층 위 — **SQL 자체를 (대부분) 감춘다.** 객체 상태 변화를 보고 INSERT/UPDATE/DELETE를 **생성**한다.

---

## 2. 핵심 메커니즘 — 같은 CRUD, 반대 방향

같은 "회원 이름 수정"을 두 방식으로:

### MyBatis — SQL이 주인공
```xml
<!-- Mapper XML: SQL이 코드 밖에 그대로 노출 -->
<update id="updateName">
  UPDATE member SET name = #{name} WHERE id = #{id}
</update>
```
```java
memberMapper.updateName(id, "새이름");  // 이 SQL이 그대로 나감
```

### JPA — 객체가 주인공, SQL은 생성됨
```java
@Transactional
void rename(Long id, String name) {
    Member m = em.find(Member.class, id); // SELECT (영속 상태로 관리 시작)
    m.setName(name);                       // 자바 객체만 바꿈. UPDATE 호출 없음(!)
    // 트랜잭션 커밋 시점에 Hibernate가 스냅샷과 비교(더티 체킹)해
    //   UPDATE member SET name=? WHERE id=?  를 "알아서" 생성·실행
}
```
- **MyBatis: 내가 쓴 SQL이 그대로 실행** → 예측 100%.
- **JPA: `setName` 한 줄이 UPDATE로 번역됨** → 편하지만 "언제 어떤 SQL이 나가는지"를 이해해야 함(플러시 타이밍). 이 간극이 JPA의 편함과 함정의 근원.

---

## 3. JPA만의 무기 (MyBatis엔 없거나 수동인 것)

이게 "굳이 JPA를 왜"에 대한 실질적 답이다.

1. **영속성 컨텍스트 = 1차 캐시 + 변경 감지(더티 체킹)**
   - 트랜잭션 안에서 조회한 엔티티를 관리 상태로 두고, **필드만 바꾸면 UPDATE를 자동 생성.** 반복 SQL이 사라진다. (→ [persistence-context-and-n-plus-one.md](persistence-context-and-n-plus-one.md))
   - 같은 트랜잭션·같은 ID 조회는 캐시로 **동일성(identity) 보장**.
2. **쓰기 지연(transactional write-behind)** — INSERT/UPDATE를 모아 커밋 시점에 flush → **JDBC batch**로 묶어 보낼 여지.
3. **지연 로딩(lazy loading)** — 연관 엔티티를 실제 접근할 때 조회. 객체 그래프를 자연스럽게 탐색. (양날의 검 → 5장 N+1)
4. **JPQL / Criteria / QueryDSL** — 테이블이 아니라 **엔티티(객체)를 대상으로** 쿼리. `QueryDSL`을 얹으면 **컴파일 타임 타입 안전** 쿼리.
5. **DB 방언(Dialect) 추상화** — MySQL↔PostgreSQL 등 교체 시 페이징·함수 차이를 구현체가 흡수(단, 네이티브 SQL을 많이 쓰면 이 이점은 줄어듦 — 조건부).
6. **표준 명세라 이식성** — 구현체(Hibernate↔EclipseLink)를 바꿔도 표준 API 코드는 유지.

> 요지: **반복 CRUD·도메인 모델링·낙관적 락·캐시 같은 "공통 배관"을 프레임워크가 대신 깔아준다.** MyBatis라면 이걸 대부분 손으로 SQL을 써서 채워야 한다.

---

## 4. MyBatis의 무기 (JPA가 서툰 것)

1. **복잡한 조회·통계에 강함** — 다중 조인, 서브쿼리, 윈도우 함수, GROUP BY 집계 등을 **손으로 튜닝한 SQL 그대로** 쓴다. JPQL로 표현하기 버겁거나 불가능한 쿼리도 자유.
2. **동적 SQL** — `<if> <choose> <foreach> <where>`로 조건 조합(검색 필터 N개)을 XML에서 조립. 복잡한 동적 조건에서 특히 강함.
3. **예측 가능성·리뷰 용이** — 실행되는 SQL이 눈에 그대로 보인다 → 성능 예측·실행계획 분석·코드리뷰가 직관적. (JPA는 생성된 SQL을 로그로 확인해야 하고 N+1·플러시 등 숨은 동작을 알아야 함)
4. **레거시 DB·기존 SQL 자산과 궁합** — 이미 튜닝된 SQL, 저장 프로시저, 비정규화 스키마를 그대로 흡수. 엔티티 매핑을 강요하지 않음.
5. **낮은 학습 곡선(초기)** — SQL을 아는 사람이면 "SQL + 매핑"만 이해하면 됨. JPA는 영속성 컨텍스트·flush·cascade·fetch 전략 등 개념 부채가 큼.

---

## 5. 트레이드오프 정리 + JPA의 대표 함정(N+1)

| 축 | **JPA(ORM)** | **MyBatis(SQL Mapper)** |
|--|--|--|
| SQL 통제권 | 프레임워크가 생성(감춰짐) | **개발자 100% 통제** |
| 단순 CRUD | **자동 생성 → 코드 최소** | 매번 SQL 작성(반복↑) |
| 복잡 조회·통계 | JPQL 한계·네이티브로 우회 | **강함(자유로운 SQL)** |
| 도메인 모델링 | **객체지향·연관관계·상속 표현** | 매핑에 그침(빈약) |
| 학습 곡선 | **가파름**(숨은 동작 이해 필요) | 완만(SQL 알면 시작) |
| 예측성·튜닝 | 생성 SQL을 봐야, N+1 주의 | **실행 SQL이 그대로 보임** |
| DB 이식성 | 방언으로 흡수(조건부) | SQL이 DB에 묶임 |
| 대표 리스크 | **N+1, OSIV 커넥션 점유, 플러시 오해** | 반복 SQL·매핑 실수·SQL-DB 결합 |

### JPA의 N+1 문제 (면접 단골)
- **증상:** 연관 엔티티를 지연 로딩할 때, 목록 N건을 돌며 연관을 건드리면 쿼리가 **1 + N**번 나간다.
```java
List<Order> orders = repo.findAll();        // 쿼리 1번 (주문 10건)
for (Order o : orders) o.getMember().getName(); // 주문마다 회원 조회 → +10번 = 총 11번 💥
```
- **원인:** "객체 그래프를 편하게 탐색"이라는 지연 로딩의 편함이, 숨은 SQL 폭증으로 되돌아옴.
- **대응:** `fetch join`(JPQL), `@EntityGraph`, `hibernate.default_batch_fetch_size`(IN 절로 묶기), 조회 전용은 DTO 프로젝션.
- **교훈:** JPA는 **"쉽게 시작하지만 제대로 쓰려면 내부를 알아야" 하는** 도구. MyBatis엔 이 문제가 없다(SQL을 내가 짜니까) — 대신 그 SQL을 매번 내가 짜야 한다.

---

## 6. 언제 무엇을 — 그리고 혼용(둘 다 쓰기)

- **JPA가 유리:** 도메인 로직이 풍부하고 CRUD가 많은 서비스, 객체지향 설계·DDD, 빠른 개발 속도, 다양한 DB 지원이 필요할 때.
- **MyBatis가 유리:** 복잡한 조회·대량 통계·리포트가 핵심, SQL을 손으로 튜닝해야 하는 성능 민감 구간, 레거시 DB/기존 SQL 자산 위에 얹을 때.
- **혼용(실무에서 흔함):** 명령/CRUD·도메인은 **JPA**, 복잡 조회·통계는 **MyBatis(또는 QueryDSL/JdbcTemplate)** 로 분리. **쓰기는 ORM, 읽기는 SQL**로 가르는 CQRS 성격의 분리. 상호 배타가 아니다.
  - JPA 진영 안에서 복잡 쿼리를 풀고 싶으면 **QueryDSL**이 1순위 대안(타입 안전 + 동적 쿼리). MyBatis까지 안 가고 해결되는 경우도 많다.

---

## 7. 성능 오해 — "MyBatis가 빠르다?"

- **본질적으로 한쪽이 빠른 게 아니다.** 둘 다 결국 **JDBC** 위에서 같은 SQL을 DB로 보낸다. 같은 SQL이면 DB가 하는 일은 같다.
- JPA는 **더티 체킹·1차 캐시·프록시** 같은 오버헤드를 얹지만, 반대로 **쓰기 지연 + JDBC batch**로 다건 쓰기를 묶어 **더 빠를** 수도 있다.
- MyBatis는 매핑이 얇아 단순 조회에서 오버헤드가 적지만, 그건 "JPA를 잘 못 썼을 때(N+1 방치 등)"와의 비교인 경우가 많다.
- **결론:** "어느 게 빠르냐"는 **쿼리·설정·사용 숙련도**에 달렸지 프레임워크 간판으로 정해지지 않는다. (수치화된 단일 우열 주장은 신뢰하지 말 것 — 확인 안 됨.)

---

> ## 📌 핵심 요약
> **MyBatis = SQL Mapper**(내가 SQL 쓰고 결과만 매핑, 예측·튜닝·복잡조회 강함), **JPA = ORM 표준 명세**(객체 매핑 선언 → SQL 자동 생성, 영속성 컨텍스트·더티 체킹·지연 로딩·낙관적 락 같은 공통 배관을 대신 깔아줌). "굳이 JPA?"의 답 = **반복 CRUD 제거 + 도메인 객체 중심 설계 + DB 이식성**. 대가는 **가파른 학습 곡선과 N+1 같은 숨은 함정**. 갈림길은 우열이 아니라 **도메인 복잡도(→JPA) vs 쿼리 복잡도(→MyBatis)** 이고, **쓰기=JPA·읽기=MyBatis/QueryDSL 혼용**도 정당하다. 성능은 둘 다 JDBC 위라 간판으로 안 갈린다.

> ## 🔗 참고 자료
> - Jakarta Persistence 명세 (jakarta.ee/specifications/persistence) — JPA는 "명세"라는 사실의 1차 출처
> - Hibernate User Guide — *Persistence Context / Fetching(N+1·EntityGraph) / Dialect*
> - MyBatis 공식 문서 (mybatis.org/mybatis-3) — *Getting Started / Dynamic SQL*
> - 김영한 『자바 ORM 표준 JPA 프로그래밍』 — ORM 개념·영속성 컨텍스트·JPQL 전반

> ## 🌱 심화 키워드
> - **영속성 컨텍스트 / 더티 체킹 / 쓰기 지연 / 1차 캐시** — JPA가 "굳이" 주는 것들 (→ 관련 노트)
> - **N+1 / fetch join / @EntityGraph / default_batch_fetch_size** — JPA 최대 함정과 해법
> - **JPQL / Criteria / QueryDSL** — 객체 대상 쿼리, MyBatis 안 가고 복잡 쿼리 풀기
> - **OSIV(Open Session In View)** — JPA 특유의 커넥션 점유 이슈
> - **CQRS / 읽기·쓰기 모델 분리** — JPA·MyBatis 혼용의 이론적 배경
> - **iBATIS → MyBatis / Hibernate·EclipseLink** — 각 진영의 계보·구현체

> ## ❓ 남은 질문
> 1. JPA에서 복잡 조회는 **QueryDSL로 어디까지** 커버되고, **언제 MyBatis/네이티브 SQL**로 내려가야 하나? (경계선 감각)
> 2. 혼용 시 **트랜잭션·영속성 컨텍스트 경계**를 어떻게 관리하나? (MyBatis로 UPDATE한 걸 JPA 영속성 컨텍스트가 모르는 stale 문제)
> 3. N+1을 근본적으로 줄이는 실무 기본값 세팅은? (`default_batch_fetch_size`, DTO 프로젝션 원칙 — [persistence-context-and-n-plus-one.md](persistence-context-and-n-plus-one.md)와 연결)
