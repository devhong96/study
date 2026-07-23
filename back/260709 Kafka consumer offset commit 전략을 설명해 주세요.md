# 260709 : Kafka consumer offset commit 전략을 설명해 주세요.

Kafka consumer offset commit 전략을 설명해 주세요.

이 질문은 Kafka를 단순히 “메시지 큐처럼 사용해봤는지”보다, 메시지 처리의 신뢰성과 장애 상황을 어떻게 설계했는지 확인하는 질문에 가깝습니다.

좋은 답변에는 이런 흐름이 들어가면 좋습니다.

- Kafka consumer는 topic partition에서 메시지를 읽고, 어디까지 처리했는지를 offset으로 관리합니다.
- Offset commit은 “이 offset까지는 처리했다”는 정보를 Kafka에 기록하는 과정입니다.
- Auto commit은 설정된 주기마다 자동으로 offset을 commit하기 때문에 구현은 간단하지만, 실제 처리가 끝나기 전에 commit될 수 있습니다.
- Manual commit은 메시지 처리가 성공한 뒤 직접 commit하므로 안정성을 더 세밀하게 제어할 수 있습니다.
- 장애 상황을 고려하면 보통 중요한 데이터는 처리 성공 이후 manual commit을 사용하고, 중복 처리를 대비해 멱등성도 함께 설계합니다.

꼬리 질문으로는 이런 것들이 나올 수 있습니다.

- Auto Commit의 위험성은 무엇인가요?
- Manual Commit을 사용해도 메시지 중복이 발생할 수 있나요?
- 메시지 처리는 성공했는데 offset commit이 실패하면 어떻게 되나요?
- At-least-once와 at-most-once는 offset commit 시점과 어떤 관계가 있나요?
- 중복 메시지를 방어하려면 어떤 기준으로 멱등성 key를 설계해야 하나요?

---

## 답변

> **한 줄 핵심**: 재시작·리밸런스 후에는 "커밋된 offset부터" 다시 읽는다 — 그래서 **처리와 커밋의 선후 관계가 곧 신뢰성 수준**이다: 처리 후 커밋 = at-least-once(중복 가능), 처리 전 커밋 = at-most-once(유실 가능).

### 1문 1답

**Q. Kafka consumer offset commit 전략을 설명해 주세요.**

**A.** Kafka consumer는 파티션별로 어디까지 읽었는지를 offset으로 관리하고, commit은 그 위치를 내부 토픽 __consumer_offsets에 기록하는 행위다. 재시작·리밸런스 후에는 커밋된 offset부터 다시 읽으므로 언제 커밋하느냐가 곧 유실·중복의 방향을 정한다 — 처리 후 커밋은 at-least-once(중복 가능), 처리 전 커밋은 at-most-once(유실 가능)다. Auto commit은 기본 5초 주기로 자동 커밋되는데, 커밋 시점을 처리 완료와 무관하게 시간이 정하므로 처리 안 된 offset이 커밋돼 crash 시 유실되거나 마지막 커밋 이후 처리분이 재시작 시 중복될 수 있다. Manual commit은 처리 성공을 확인한 뒤 commitSync(성공까지 재시도하지만 블로킹)나 commitAsync(빠르지만 재시도 안 함 — 오래된 커밋의 재시도가 새 커밋을 덮는 순서 역전을 막기 위함)로 직접 커밋하며, 평상시 commitAsync에 리밸런스·종료 시점 commitSync 조합이 흔하다. 실무 결론은 중요한 데이터는 처리 성공 후 manual commit으로 at-least-once를 확보하고 그로 인해 생기는 중복은 consumer 멱등성으로 흡수하는 것이다(참고로 Spring Kafka는 auto commit을 끄고 컨테이너 AckMode로 커밋을 관리하는 것이 기본).

**Q. Kafka consumer의 offset과 offset commit이란 무엇인가요?**

**A.** consumer는 topic partition에서 메시지를 읽으며 어디까지 처리했는지를 offset으로 관리합니다. commit은 그 위치, 즉 "이 offset까지 처리했다"는 정보를 Kafka 내부 토픽 __consumer_offsets에 기록하는 행위입니다. 이 기록이 중요한 이유는 재시작이나 리밸런스가 일어나면 consumer가 커밋된 offset부터 다시 읽기 때문입니다. 그래서 처리와 커밋의 선후 관계가 곧 신뢰성 수준을 결정합니다 — 언제 커밋하느냐에 따라 유실이 날지 중복이 날지 방향이 갈립니다.

**Q. Auto commit은 어떻게 동작하며 무엇이 위험한가요?**

**A.** enable.auto.commit=true일 때 기본 5초 주기로 poll 과정에서 자동 커밋되므로 구현은 간단합니다. 문제는 커밋 시점을 처리 완료와 무관하게 "시간"이 결정한다는 점, 즉 커밋이 더 이상 "처리 완료의 증거"가 아니게 된다는 것입니다. 레코드를 다른 스레드에 넘기고 계속 poll하는 구조면 처리 안 된 offset이 커밋돼 crash 시 유실될 수 있고, 동기 루프여도 마지막 커밋 이후 처리분은 재시작 시 중복됩니다. 두 위험 중 특히 유실이 치명적인데, 중복은 멱등성으로 막을 수 있어도 이미 커밋된 offset 뒤로 되돌아갈 계기가 없어 유실은 복구 수단이 없기 때문입니다.

**Q. Manual commit은 무엇이 다르고 어떤 이점이 있나요?**

**A.** Manual commit은 메시지 처리 성공을 확인한 뒤 commitSync나 commitAsync로 직접 커밋하므로, 커밋 시점을 "시간"이 아니라 "처리 완료" 기준으로 세밀하게 제어할 수 있습니다. commitSync는 성공까지 재시도하는 대신 블로킹이고, commitAsync는 빠르지만 재시도를 하지 않습니다. commitAsync가 재시도를 안 하는 이유는 오래된 커밋의 재시도가 새 커밋을 덮어 offset이 되감기는 순서 역전을 막기 위해서입니다. 그래서 평상시에는 commitAsync를 쓰고 리밸런스·종료 시점에만 commitSync로 확실히 마무리하는 조합이 흔한 패턴입니다.

**Q. 실무에서는 보통 어떤 커밋 전략을 쓰나요?**

**A.** 중요한 데이터는 처리 성공 이후 manual commit으로 at-least-once를 확보하고, 그로 인해 필연적으로 생기는 중복은 consumer 멱등성으로 흡수하는 것이 표준입니다. 처리와 커밋은 서로 다른 시스템에 대한 두 행위라 원자적으로 묶을 수 없어 중복 자체를 없앨 수는 없기 때문입니다. 그래서 "at-least-once + 멱등성"으로 사실상의 exactly-once 효과를 만드는 접근이 일반적입니다. 참고로 Spring Kafka는 auto commit을 끄고 컨테이너의 AckMode로 커밋을 관리하는 것이 기본 동작입니다.

**Q. Manual Commit을 사용해도 메시지 중복이 발생할 수 있나요?**

**A.** 예 — "처리 성공 → 커밋 직전 crash/리밸런스" 구간이 존재하는 한 재전달은 필연입니다. 처리와 커밋은 서로 다른 시스템에 대한 두 행위라 원자적으로 묶을 수 없기 때문입니다(dual write와 같은 구조). 즉 둘 사이의 crash 구간을 0으로 만들 수는 없고, 어느 쪽에 위험을 둘지 선택만 가능합니다. 이것이 at-least-once의 본질이고, 그래서 중복 제거는 커밋 전략의 문제가 아니라 멱등성의 몫입니다.

**Q. 메시지 처리는 성공했는데 offset commit이 실패하면 어떻게 되나요?**

**A.** 커밋이 안 됐으므로 재시작·리밸런스 후 같은 메시지를 다시 받아 중복 처리됩니다. 이는 처리 후 커밋 구조에서 유실이 아니라 중복 방향으로 위험이 나타나는 전형적인 경우입니다. commitSync는 네트워크 순단 같은 일시적 오류는 내부 재시도로 넘어가므로, 커밋 실패가 계속 반복된다면 단순 순단이 아니라 이미 파티션 소유권을 잃은 리밸런스 상황이거나 브로커 장애를 의심해야 합니다. 결국 이 중복도 consumer 멱등성으로 흡수하는 것이 정답입니다.

**Q. At-least-once와 at-most-once는 offset commit 시점과 어떤 관계가 있나요?**

**A.** 처리 후 커밋이면 at-least-once(유실 없음, 중복 가능), 처리 전 커밋이면 at-most-once(중복 없음, 유실 가능)입니다. "유실 없음"의 근거는 처리 못 한 메시지는 커밋도 안 됐으니 반드시 다시 온다는 것이고, "중복 없음"의 근거는 받자마자 커밋했으니 다시 오지 않는다는 것입니다. 대신 at-most-once는 처리에 실패하면 그걸로 끝이라 복구가 없습니다. 그래서 두 방식은 우열이 아니라, 도메인에서 유실과 중복 중 어느 쪽 위험이 더 아픈지에 따른 선택의 문제입니다.

**Q. 중복 메시지를 방어하려면 어떤 기준으로 멱등성 key를 설계해야 하나요?**

**A.** "논리적으로 같은 메시지"를 식별할 수 있는 키여야 합니다. 프로듀서가 부여한 이벤트 고유 ID나 비즈니스 키(주문ID + 이벤트타입)가 정석이고, (topic, partition, offset) 조합도 재전달 시 동일하게 유지되는 자연 키가 됩니다. 가장 강한 방식은 처리 결과와 처리 이력(키)을 같은 DB 트랜잭션으로 저장하는 것입니다. 그래야 "반영됐는데 이력이 없다"는 틈 자체가 DB 원자성으로 사라지고, 재전달이 와도 unique 제약에 걸려 안전하게 스킵됩니다.

### 면접 답변 (구술용)

Kafka consumer는 파티션별로 어디까지 읽었는지를 offset으로 관리하고, commit은 그 위치를 내부 토픽 __consumer_offsets에 기록하는 행위입니다. 재시작이나 리밸런스 후에는 커밋된 offset부터 다시 읽기 때문에, 언제 커밋하느냐가 곧 유실과 중복의 방향을 결정합니다. Auto commit은 기본 5초 주기로 poll 과정에서 자동 커밋되는데, 문제는 커밋 시점을 처리 완료와 무관하게 시간이 결정한다는 것입니다 — 레코드를 다른 스레드에 넘기고 계속 poll하는 구조면 처리 안 된 offset이 커밋돼 crash 시 유실될 수 있고, 동기 루프여도 마지막 커밋 이후 처리분은 재시작 시 중복됩니다. Manual commit은 처리 성공을 확인한 뒤 commitSync나 commitAsync로 직접 커밋합니다 — commitSync는 성공까지 재시도하는 대신 블로킹이고, commitAsync는 빠르지만 재시도를 안 하는데 이유는 오래된 커밋의 재시도가 새 커밋을 덮어 offset이 되감기는 순서 역전을 막기 위해서입니다. 그래서 평상시 commitAsync에 리밸런스·종료 시점 commitSync 조합이 흔한 패턴입니다. 실무 결론은 — 중요한 데이터는 처리 성공 후 manual commit으로 at-least-once를 확보하고, 그로 인해 필연적으로 생기는 중복은 consumer 멱등성으로 흡수합니다. 참고로 Spring Kafka는 auto commit을 끄고 컨테이너의 AckMode로 커밋을 관리하는 것이 기본 동작입니다(거의 확실).

### 원리 이해 (왜 그런가)

**커밋 시점 = 신뢰성 수준의 결정:**

```
[처리 후 커밋]  poll → 처리 ✓ → commit
  crash 지점이 처리~커밋 사이면? → 커밋 안 됨 → 재전달 → "중복" (유실 없음) = at-least-once
[처리 전 커밋]  poll → commit → 처리
  crash 지점이 커밋~처리 사이면? → 커밋 됨 → 재전달 없음 → "유실" (중복 없음) = at-most-once
※ "처리와 커밋"은 서로 다른 시스템에 대한 두 행위라 원자적으로 묶을 수 없다 (dual write와 같은 구조)
  → 둘 사이 crash 구간을 0으로 만들 수 없고, 어느 쪽에 위험을 둘지 "선택"만 가능하다
```

**Auto vs Manual 비교:**

| | Auto commit | Manual commit |
|---|---|---|
| 방식 | `enable.auto.commit=true`, `auto.commit.interval.ms`(기본 5000) 주기로 poll 중 자동 커밋 | 처리 성공 후 commitSync / commitAsync |
| 커밋 시점 제어 | 불가 (시간 기준) | 가능 (처리 완료 기준) |
| 위험 | 비동기 처리 구조에서 유실 가능 + 중복 | 중복만 (유실 없음) |
| commitSync | — | 성공까지 재시도, blocking |
| commitAsync | — | non-blocking, **재시도 안 함**(순서 역전 방지), 콜백으로 실패 감지 |

**exactly-once는?** Kafka 안에서 완결되는 read-process-write 파이프라인(예: Kafka Streams)은 Kafka 트랜잭션으로 가능하지만, 외부 DB·API가 개입하는 일반 consumer는 그 경계를 넘는 원자성이 없습니다. 표준 접근은 "at-least-once + 멱등성"으로 사실상의 exactly-once 효과를 만드는 것입니다.

### 꼬리질문 Q&A

**Q. Auto Commit의 위험성은 무엇인가요?**

**A.** **커밋이 "처리 완료의 증거"가 아니게 된다는 것.**
처리 전 커밋이면 crash 시 유실(at-most-once 방향), 처리 후 커밋 지연이면 중복이 생기는데, 특히 유실이 치명적입니다 — 중복은 멱등성으로 막을 수 있지만, 이미 커밋된 offset 뒤로 되돌아갈 계기가 없어서 유실은 복구 수단이 없기 때문입니다.

**Q. Manual Commit을 사용해도 중복이 발생할 수 있나요?**

**A.** **예 — "처리 성공 → 커밋 직전 crash/리밸런스" 구간이 존재하는 한 재전달은 필연이다.**
처리와 커밋은 서로 다른 시스템에 대한 두 행위라 원자적으로 묶을 수 없습니다. 이것이 at-least-once의 본질이고, 그래서 중복 제거는 커밋 전략이 아니라 멱등성의 몫입니다.

**Q. 처리는 성공했는데 offset commit이 실패하면?**

**A.** **커밋이 안 됐으므로 재시작·리밸런스 후 같은 메시지를 다시 받아 중복 처리된다.**
commitSync는 일시적 오류(네트워크 순단)에는 내부 재시도로 넘어가므로, 커밋 실패가 계속된다면 이미 파티션 소유권을 잃은 리밸런스 상황이나 브로커 장애를 의심해야 합니다.

**Q. at-least-once와 at-most-once는 커밋 시점과 어떤 관계인가요?**

**A.** **처리 후 커밋 = at-least-once(유실 없음, 중복 가능), 처리 전 커밋 = at-most-once(중복 없음, 유실 가능).**
"유실 없음"의 근거: 처리 못 한 메시지는 커밋도 안 됐으니 반드시 다시 옵니다. "중복 없음"의 근거: 받자마자 커밋했으니 다시 오지 않습니다 — 대신 처리 실패하면 그걸로 끝입니다. 도메인에서 어느 쪽 위험이 더 아픈지가 선택 기준입니다.

**Q. 중복 방어용 멱등성 key는 어떤 기준으로 설계하나요?**

**A.** **"논리적으로 같은 메시지"를 식별할 수 있는 키 — 프로듀서가 부여한 이벤트 고유 ID나 비즈니스 키(주문ID + 이벤트타입)가 정석이다.**
(topic, partition, offset) 조합도 재전달 시 동일하게 유지되는 자연 키가 됩니다. 가장 강한 방식은 처리 결과와 처리 이력(키)을 같은 DB 트랜잭션으로 저장하는 것 — "반영됐는데 이력이 없다"는 틈 자체를 DB 원자성으로 제거하므로, 재전달이 와도 unique 제약에 걸려 안전하게 스킵됩니다.

### 🌱 심화 키워드
- **__consumer_offsets** — 커밋된 offset이 저장되는 Kafka 내부 compacted 토픽
- **리밸런스 / ConsumerRebalanceListener** — 파티션 소유권 이동 시 커밋을 마무리하는 훅
- **cooperative sticky assignor** — 전체 정지 없는 점진적 리밸런싱
- **Kafka transactions / read_committed** — Kafka 내 exactly-once의 구성 요소
- **idempotent consumer** — at-least-once의 중복을 흡수하는 소비자 설계 (→ 260710)

### 🔗 참고 자료
- Apache Kafka 공식 문서 — Consumer Configs(enable.auto.commit, auto.commit.interval.ms), "Offsets and Consumer Position"
- 카프카 핵심 가이드 (Kafka: The Definitive Guide) — 컨슈머·신뢰성 챕터
- Spring for Apache Kafka 공식 문서 — Committing Offsets / AckMode

### ❓ 더 파볼 질문

**Q. cooperative sticky 리밸런싱은 기존(eager) 방식과 뭐가 다른가?**

**A.** eager는 리밸런스 때 전원이 모든 파티션을 내려놓고 재배정받는 stop-the-world 방식이라 그 동안 소비가 멈춘다. cooperative는 이동이 필요한 파티션만 점진적으로 넘겨서 나머지 파티션의 소비가 계속된다 — 리밸런스 빈도가 높은 대규모 그룹에서 체감 차이가 크다.

**Q. 특정 지점부터 다시 처리하고 싶으면 어떻게 하나?**

**A.** consumer의 seek()로 원하는 offset(또는 타임스탬프 기반 offsetsForTimes)으로 되감아 재소비한다. Kafka가 로그를 보존 기간 동안 들고 있기에 가능한 기능으로, "재처리 가능성"이 Kafka를 큐가 아니라 로그라고 부르는 이유다.

**Q. Kafka 트랜잭션의 zombie fencing이란?**

**A.** 같은 transactional.id로 새 프로듀서가 시작되면 epoch가 올라가고, 이전 세대(좀비) 프로듀서의 쓰기·커밋을 브로커가 거부한다. "죽은 줄 알았던 옛 인스턴스가 뒤늦게 쓰는" 문제 — 분산락의 늦은 쓰기(260706)와 같은 계열의 문제를 Kafka는 epoch로 푸는 것이다.
