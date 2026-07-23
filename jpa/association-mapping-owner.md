# 연관관계 매핑 & 연관관계의 주인 (mappedBy)

> **한 줄 정의:** 양방향 연관관계에서 *"객체는 양쪽 참조(둘), DB는 FK 하나"*의 불일치를 해결하려, **FK를 실제로 가진 쪽 하나만 "주인"으로 정해 FK를 제어**하고 반대편(`mappedBy`)은 **DB에 실체 없는 읽기 전용 거울**로 둔다.

> 관련 문서:
> - [persistence-context-and-n-plus-one.md](persistence-context-and-n-plus-one.md) — 양방향이 N+1·직렬화 무한순환의 원인이 되는 맥락
> - [em-threadlocal-transaction.md](em-threadlocal-transaction.md) — 1차 캐시·flush(여기서 "객체 상태 ≠ DB 상태"가 갈림)

---

## 1. 출발점 — "객체는 둘, FK는 하나"

`Team`(1) : `Member`(N) 양방향:

```java
@Entity
class Member {
    @ManyToOne @JoinColumn(name = "team_id")
    private Team team;                                  // N쪽 — FK 보유
}
@Entity
class Team {
    @OneToMany(mappedBy = "team")
    private List<Member> members = new ArrayList<>();   // 1쪽 — 거울
}
```

- 객체 세계: `member.getTeam()` ↔ `team.getMembers()` — **양쪽에서 서로 참조(둘).**
- DB 세계: `MEMBER.team_id` **FK 컬럼 딱 하나.**
- 이 불일치 때문에 "둘 중 누가 FK를 책임지나"를 정해야 함 → **연관관계의 주인**.

---

## 2. mappedBy & 주인 — 가장 헷갈리는 지점 (정반대로 알기 쉬움)

> ⚠️ **`mappedBy`가 붙은 쪽 = 주인이 "아닌" 쪽이다.** (주인이란 뜻 아님 — 정반대)

`mappedBy`는 *"나는 주인이 아니고, 저쪽 필드한테 매핑을 맡겼다(mapped **by** ~)"*는 선언. 그 값은 **FK가 아니라 주인 엔티티의 "필드 이름"**.

```java
@OneToMany(mappedBy = "team")   // "Member 엔티티의 'team' 필드가 주인이다"
```

| | **주인 (owner)** | **주인 아님 (inverse / 거울)** |
|--|--|--|
| 누구 | `Member.team` | `Team.members` |
| 표시 | `@JoinColumn`, **mappedBy 없음** | **mappedBy 있음** |
| DB 컬럼 | FK(`team_id`) **직접 매핑·제어** | **대응 컬럼 없음** (실체 없음) |
| 할 수 있는 것 | 읽기 + **FK 쓰기** | **읽기(탐색)만** |

**왜 주인을 정하나?** 참조는 둘인데 FK는 하나 → 둘 다 FK를 수정하게 두면 값이 어긋날 때 **JPA가 뭘 DB에 반영할지 모름**. 그래서 **FK 제어권을 한 쪽에만** 준다. → **FK를 실제로 가진 쪽(`@ManyToOne`, N쪽 Member)이 자연스러운 주인.**

---

## 3. 주인 아닌 쪽엔 왜 DB 컬럼이 없나 (DDL로 확인되는 본질)

`ddl-auto`로 생성해보면:
- `Member.team`(`@JoinColumn`) → `MEMBER` 테이블에 **`team_id` FK 컬럼 생성.** ✅
- `Team.members`(`@OneToMany mappedBy`) → **아무 컬럼도 안 생김.** ✅

**이유**: 1:N에서 FK는 **항상 N쪽(Member) 테이블**에 산다. 한 팀에 멤버가 여럿인데 `TEAM` 테이블 컬럼 하나에 여러 멤버 id를 못 담으니까. → 관계는 물리적으로 **`MEMBER.team_id` 하나로만** 표현됨.

→ 그래서 **`Team.members`는 DB 컬럼이 아니라 "애플리케이션(객체) 레벨의 탐색 편의"**다. `team.getMembers()` 호출 시 JPA가 *"`team_id = ?`인 Member를 SELECT"*해서 채워줄 뿐, 어떤 컬럼을 읽는 게 아니다.
→ **제어할 FK 컬럼 자체가 없으니** 주인이 못 되고 읽기 전용. ("주인 아닌 쪽이 FK를 못 쓰는" 물리적 이유.)

---

## 4. 단골 함정 — 주인만 세팅하고 거울은 깜빡

```java
member.setTeam(team);            // 주인 세팅 → team_id UPDATE ✅
// team.getMembers().add(member); // ← 깜빡!
```

- **DB 저장은?** → **잘 된다.** 주인(`Member.team`)을 세팅했으니 flush 때 `team_id`가 정상 기록. DB 관점에선 주인만 세팅하면 끝.
- **같은 트랜잭션에서 `team.getMembers()` 조회하면?** → **안 보인다.**
  - 그 `team`은 이미 영속 상태로 **1차 캐시(메모리)**에 있고, `members`는 그냥 자바 리스트.
  - `add()`를 안 했으니 리스트엔 member가 없음. **flush는 DB FK만 갱신하지, 메모리의 `team.members` 리스트를 자동으로 안 채워준다.**
  - → **JPA는 양방향을 자동 동기화하지 않는다.** "DB엔 관계 있는데 객체엔 없는" **객체 상태 ≠ DB 상태** 불일치 발생.

**정석 — 연관관계 편의 메서드로 양쪽 동기화:**
```java
public void setTeam(Team team) {
    this.team = team;
    team.getMembers().add(this);   // 거울도 맞춤 → 객체 일관성
}
```
> DB만 보면 주인 세팅으로 충분하지만, **같은 트랜잭션 안에서 객체를 다시 읽는 순간** 위 불일치가 터지므로 둘 다 맞춘다.

### 4-1. "안 보임"의 진짜 원인 — DB가 아니라 메모리 거울이 stale

DB의 `team_id`는 **주인 세팅 후 flush 시점부터 이미 정상**이다. "안 보임"은 DB가 틀려서가 아니라 **메모리의 `team.members` 리스트가 stale**해서일 뿐.
```
DB:           team_id 박힘 ✅ (flush 시점부터)
메모리 컬렉션: add() 안 했으니 비어있음 ❌  ← 안 보였던 진짜 원인
```
- **커밋 후엔 보이나?** → 보인다. 단 이유는 *커밋이라는 행위*가 아니라 **새 트랜잭션 = 새 영속성 컨텍스트가 stale 거울을 버리고 DB를 다시 SELECT** 하기 때문(1차 캐시 소멸 → 재조회).
- **같은 TX 안에서도** 컬렉션을 그때까지 한 번도 초기화 안 했으면 flush 후 첫 접근에 DB를 읽어 보일 수도 있다. 즉 **"컬렉션 초기화 시점"에 따라 들쭉날쭉** → 이 불확실성 자체가 문제.

### 4-2. "어차피 다시 읽으면 되는데 편의 메서드가 꼭 필요한가?" (정직한 답)

**필수가 아닌 경우**: *write 후 항상 새 트랜잭션(새 컨텍스트)에서 재조회*만 한다면, DB가 진실원천이라 편의 메서드 없이도 정합성은 맞는다. (이 지적은 옳다.)

**그래도 필요한 경우** (항상 다시 읽지는 않으니까):
1. **같은 트랜잭션에서 그 객체를 계속 쓸 때** — 재조회가 아니라 메모리 `team`을 그대로 재사용 → stale 컬렉션으로 검증·집계·DTO 변환이 틀어짐. (가장 흔함)
2. **부모 주도 cascade** — `CascadeType.PERSIST`는 **메모리 컬렉션**을 보고 자식을 저장. 컬렉션에 안 넣으면 cascade가 자식을 못 봄. (orphanRemoval도 컬렉션 상태 기준)
3. **DB 없는 단위 테스트** — 객체만으로 양방향 일관성을 기대.

> **결론**: 편의 메서드 = **정합성 보험**. "맹목적으로 항상 필수"가 아니라, **같은 TX 객체 재사용·cascade에서 필요**하고 그게 언제일지 예측이 어려우니 **습관**으로 양방향을 맞춰 버그 클래스를 통째로 없애는 것. 비용은 한 줄, 안 했을 때 버그는 추적이 까다로움.
>
> *면접 답변 예*: "DB만 보면 주인 세팅으로 충분하지만, 같은 트랜잭션 내 객체 재사용·cascade 때문에 양방향을 맞춰주는 게 안전합니다."

---

## 5. 그래서 결론 — 단방향을 기본으로, 양방향은 옵션

양방향의 동기화·stale 문제를 보면 자연히 드는 생각: *"그냥 단방향만 쓰면 안 되나?"* → **맞다. `@ManyToOne` 단방향이 권장 기본값이다.**

| 선택 | 평가 |
|------|------|
| **`@ManyToOne` 단방향** | ✅ **기본값으로 권장.** FK가 N쪽에 있으니 이거 하나로 관계 완전 매핑. 편의 메서드·동기화·컬렉션 로딩 걱정 없음 |
| **양방향** (`@ManyToOne` + `@OneToMany mappedBy`) | 🔶 1쪽에서 컬렉션 탐색(`team.getMembers()`)·cascade가 *정말 필요할 때만* 추가 (+편의 메서드) |
| **`@OneToMany` 단방향** (mappedBy 없이 1쪽이 주인) | ❌ FK는 N쪽 테이블인데 주인은 1쪽 → **INSERT 후 team_id 채우는 별도 UPDATE 추가 발생.** 피하기 |

- **Vlad Mihalcea**: *"`@OneToMany`를 매핑하는 가장 좋은 방법은 `@OneToMany`를 아예 두지 않는 것"* — 자식 쪽 `@ManyToOne`만 두고, 부모→자식 목록이 필요하면 그때 **쿼리로 조회**.
- 핵심: 양방향은 "기본"이 아니라 **"필요해서 추가하는 옵션"**. 그리고 **"단방향"의 올바른 형태는 항상 FK 가진 `@ManyToOne` 쪽**이다(`@OneToMany` 단방향이 아니라).

---

## 6. cascade & orphanRemoval — 자식의 생명주기

```java
@OneToMany(mappedBy = "order", cascade = CascadeType.ALL, orphanRemoval = true)
private List<OrderItem> items = new ArrayList<>();
```

둘 다 자식 생명주기를 다루지만 **작동 트리거(언제 삭제되나)가 다르다** — 가장 헷갈리는 지점:

| | **cascade (REMOVE)** | **orphanRemoval** |
|--|--|--|
| 트리거 | **부모를 삭제**하면 → 자식도 삭제 | 자식이 **부모 컬렉션에서 빠지면**(부모는 **살아있음**) → 그 자식 삭제 |
| 개념 | "부모에게 한 일(persist/remove)을 자식에 **전파**" | "부모와 **연결 끊긴** 자식 = 고아 → 삭제" |

```java
em.remove(order);              // cascade REMOVE: items 삭제 / orphanRemoval도: items 삭제 (둘 다)
order.getItems().remove(item); // cascade: 아무 일 없음(DB에 남음) / orphanRemoval: item DELETE
```
- **두 번째 줄이 orphanRemoval만의 고유 능력** — 부모는 멀쩡한데 **컬렉션에서 빼는 것만으로 자식이 DELETE.** 즉 "자식은 이 부모 컬렉션 안에서만 존재 가능".
- 겹치는 지점: *부모 삭제* 시엔 둘 다 자식을 지운다. orphanRemoval은 거기 더해 **"연결 끊김"까지** 잡는 것.
- `cascade=false`/`orphanRemoval=false`(기본)에서 `getItems().remove()`는 **메모리 컬렉션에서만 빠지고 DB row는 그대로** 남는다(진짜 고아 row).

### ⚠️ 언제 위험한가 (`cascade=ALL + orphanRemoval=true`)
**자식의 생명주기를 부모가 완전히 독점할 때만** 안전:
1. **공유되는 자식이면 재앙** — 다른 엔티티도 참조하는 자식을 컬렉션에서 빼거나 부모를 지우면, 남이 쓰는 자식이 삭제됨. → "이 부모만의 소유물"일 때만.
2. **부모 삭제 = 자식 줄삭제**(`ALL`은 REMOVE 포함) — 의도 안 했으면 사고.
3. **컬렉션 전체 교체**(`clear()`+재삽입)면 orphanRemoval이 전부 DELETE 후 재INSERT → 대량 쿼리.

→ 안전한 전형: **Order-OrderItem, Board-Comment** 같은 *"자식이 부모 없이는 존재 의미가 없는"* 종속 관계. 자식이 독립적이거나 공유되면 **쓰지 마라.**

---

> ## 📌 핵심 요약
> 양방향은 "객체 참조 둘 vs DB FK 하나"의 불일치 → **FK 가진 쪽(`@ManyToOne`)을 주인**으로 정해 FK 제어를 독점시키고, `mappedBy` 붙은 쪽은 **DB 컬럼조차 없는 읽기 전용 거울**. 주인만 세팅하면 **DB 저장은 정상**이지만 같은 TX의 반대편 컬렉션엔 자동 반영 안 됨 → **연관관계 편의 메서드로 양쪽 동기화**. **실무 기본값은 `@ManyToOne` 단방향**, 양방향은 1쪽 탐색·cascade가 필요할 때만 옵션으로.

> ## 🔗 참고 자료
> - 김영한 『자바 ORM 표준 JPA 프로그래밍』 5~6장 (연관관계 매핑·양방향·주인)
> - Hibernate User Guide — *Associations* (`@ManyToOne`/`@OneToMany`/`mappedBy`)

> ## 🌱 심화 키워드
> - **연관관계 주인(owning side) vs 거울(inverse side)** — FK 제어권의 단일화
> - **연관관계 편의 메서드(convenience method)** — 양방향 객체 동기화
> - **`@OneToMany` 단방향의 함정** — 1쪽이 주인이면 INSERT 후 별도 UPDATE 추가 → 단방향은 `@ManyToOne` 쪽으로
> - **단방향 우선 원칙 / Vlad Mihalcea** — 양방향은 탐색·cascade 필요 시에만 옵션
> - **`@JoinColumn` vs `mappedBy`** — 어느 쪽에 무엇을 붙이나
> - **cascade vs orphanRemoval** — 트리거 차이(부모 삭제 전파 vs 연결 끊긴 고아 삭제), 공유 자식 위험 (6장)

> ## ❓ 남은 질문
> 1. `@OneToMany`를 **단방향**(`mappedBy` 없이 `@JoinColumn`만)으로 쓰면 왜 INSERT 후 별도 UPDATE 쿼리가 추가로 나갈까?
>
>    → **답:** FK 주인은 자식인데 부모 컬렉션 쪽에서 관계를 관리하니, Hibernate가 자식을 FK NULL로 먼저 INSERT한 뒤 관계를 채우는 UPDATE를 또 날린다. `@ManyToOne`(자식이 FK 주인) 양방향으로 바꾸면 INSERT 한 번으로 끝난다.
> 2. 양방향 매핑이 N+1·직렬화 무한순환의 원인이 되는 이유는? (→ N+1 노트 4-1과 연결)
>
>    → **답:** 부모→자식→부모… 참조가 순환해 JSON 직렬화가 무한 재귀에 빠지고, 지연로딩 컬렉션을 순회하면 부모마다 자식 쿼리가 나가 N+1이 된다. `@JsonIgnore`/DTO 변환과 fetch join으로 끊는다.
> 3. `cascade`와 `orphanRemoval`의 차이는? 언제 `CascadeType.ALL + orphanRemoval=true`가 위험한가?
>
>    → **답:** cascade는 부모의 영속 연산(저장·삭제)을 자식에 **전파**하고, orphanRemoval은 컬렉션에서 **빠진(연결 끊긴) 자식**을 자동 DELETE한다. 자식을 여러 부모가 공유하면 `ALL+orphanRemoval=true`는 한쪽에서 빼거나 지웠을 뿐인데 공유 자식이 통째로 삭제돼 위험하다.
