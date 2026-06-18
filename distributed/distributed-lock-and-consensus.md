# 분산 락 & 합의 & CAP (Distributed Lock, Consensus, CAP)

> **한 줄 정의:** 분산 환경에서 "단 하나만 통과시키기"를 보장하는 방법의 스펙트럼 — *Redis(시간 기반)* 에서 *ZooKeeper/etcd(합의 기반)* 까지, 그리고 그 한계를 설명하는 *CAP·선형성* 까지.

> 관련 문서:
> - [../database/transaction-and-isolation.md](../database/transaction-and-isolation.md) — 락의 출발점(단일 DB 동시성, 낙관/비관 락). **`@Version`이 곧 fencing token**.
> - [../architecture/saga-pattern.md](../architecture/saga-pattern.md) — 분산 트랜잭션을 보상 거래로 푸는 또 다른 길.

> **이 노트를 관통하는 한 가지:** 정답은 결국 **"단조 증가하는 번호로 옛 쓰기를 거부한다"** 하나로 수렴한다 — `@Version`(낙관 락) = fencing token = ZK의 zxid = etcd의 revision.

---

## 1. 왜 분산 락인가 — 락의 3계층

| 계층 | 예시 | scale-out에서 | 비고 |
|------|------|--------------|------|
| ① 애플리케이션 락 | `synchronized` | ❌ 깨짐 | JVM 안에서만 유효 |
| ② DB 락 | `FOR UPDATE`, `@Version` | ✅ 동작 | **단일 자원이면 보통 이게 최선** |
| ③ **분산 락** | Redis, ZooKeeper/etcd | ✅ | DB에 부하 주기 싫거나, 락 대상이 DB row가 아니거나, 여러 자원·노드 조율이 필요할 때 |

> 분산 락은 **가능하면 안 쓰는 게 최선**. 단일 자원의 정확성은 DB 원자적 UPDATE/낙관 락이 가장 간단·안전. 꼭 여러 자원·노드를 조율해야 할 때만 ③으로.

---

## 2. Redis 분산 락 — 함정의 계단

기본 구현: `SET lock:key "uuid" NX PX 30000` (NX=없을 때만, PX=만료 ms, 둘이 원자적) → 작업 → `DEL`.

| # | 함정 | 해결 | 그 해결이 낳는 새 함정 |
|---|------|------|----------------------|
| 1 | 락 잡고 죽으면 → 영원히 안 풀림(데드락) | **TTL(`PX`)** | TTL이 작업보다 짧으면? |
| 2 | TTL 만료 < 작업 시간 → 둘이 동시에 임계영역 | **Watchdog**(작업 중 TTL 주기적 연장, Redisson 기본) | 무한 연장 좀비 락 |
| 3 | 남의 락 삭제(만료 후 남이 잡았는데 내가 DEL) | **UUID 토큰 + Lua 원자적 해제** | — |
| 4 | Redis 마스터가 복제 전 죽으면 → 둘이 획득 | **Redlock**(독립 N대 과반 획득) | 시계·GC 가정(아래) |

```lua
-- 함정 3 해결: 내 토큰일 때만 삭제 (GET+DEL은 원자적이지 않으므로 Lua로 한 방)
if redis.call("get", KEYS[1]) == ARGV[1] then
    return redis.call("del", KEYS[1])
else return 0 end
```

---

## 3. Redlock 논쟁 — 효율 vs 정확성 (Kleppmann vs antirez)

**분산 락의 두 용도를 구분하라:**
- **효율(efficiency):** 중복 작업 방지(중복 메일 등). 어쩌다 깨져도 손해만. → **Redis로 충분**.
- **정확성(correctness):** 깨지면 데이터 손상(재고 -1, 이중 출금). → **Redis(Redlock)로도 불충분**.

**왜 불충분 — GC pause/시계 문제:**
```
T1: 락 획득 → 🛑 STW GC로 정지(자기가 멈춘 줄 모름) → TTL 만료 → 락 해제
T2: 락 획득 → 자원에 씀
T1: (깨어남) "난 아직 주인" → 자원에 씀   ← 둘 다 씀. 깨짐!
```
락은 시간(TTL)에 의존하는데 분산 환경에선 **시계도 GC 멈춤도 못 믿는다**가 비판의 핵심.

**진짜 해법 — Fencing Token:** 락마다 **단조 증가 번호** 발급 → **자원(DB/스토리지)이 "본 것보다 작은 번호의 쓰기를 거부"**. 락이 깨져도 자원 단에서 막힌다. (= `@Version`과 같은 아이디어)

---

## 4. 합의 기반 락 — ZooKeeper / etcd

Redis가 **시간**에 기댔다면, ZK/etcd는 **합의(consensus)**에 기댄다 → 강한 일관성(선형성).

### Raft (etcd) — 핵심 2단계
1. **리더 선출:** 리더 없으면 후보가 표 모음, **과반 득표**해야 리더 → 한 term에 리더 최대 1명.
2. **로그 복제:** 모든 쓰기는 리더 경유, **과반이 디스크 기록한 뒤에야 "커밋"** 인정.

```
[Client] --write--> [Leader] --복제--> [Followers]
   과반(3/5)이 기록 확인 → 커밋 확정 → 그제서야 Client에 OK
```

> **왜 과반(quorum)이 split-brain을 막나:** 5대 중 과반은 3대. **어떤 두 과반도 최소 1대가 겹친다**(3+3>5). 겹치는 노드가 두 진실을 동시에 인정 못 하니 **모순된 커밋 불가**. 네트워크가 쪼개져도 과반 못 쥔 쪽은 아예 쓰기 불가. → "시간 어림"을 **"과반 교집합이라는 수학적 보장"**으로 대체.

### ZooKeeper 락 레시피
- **Ephemeral(임시) 노드:** 세션 끊기면 자동 삭제 → "들고 죽으면?"의 우아한 해결(TTL 추측 불필요).
- **Sequential(순번) 노드:** 만들 때 단조 증가 번호 부여.
```
1. /lock/ 아래 ephemeral+sequential 노드 생성 → req-0000000003
2. 내가 제일 작은 번호인가? YES면 락 주인 🔒
3. NO면 '바로 앞 번호' 노드만 watch → 그게 삭제되면 재확인
```
> 각자 **바로 앞 노드만 watch** → 한 명 풀릴 때 수천 명이 동시에 깨는 **herd effect 회피**. (etcd는 lease에 키를 묶어 같은 효과)

---

## 5. 합의도 못 푸는 것 — 여전히 Fencing이 필요

**합의는 "락 서비스 쪽" split-brain만 막는다. "클라이언트가 멈추는" 문제는 그대로다.**
```
T1: ZK 락 획득 → 🛑 GC로 세션 타임아웃 초과 → 세션 만료로 노드 삭제 → 해제
T2: 정당하게 락 획득 → T1: (깨어남) 자원에 씀   ← 또 둘 다 씀
```
→ 결론 동일: **자원 단에서 fencing token으로 막아야** 한다. ZK는 **zxid**, etcd는 **mod_revision** 제공(둘 다 단조 증가 = `@Version`과 동일 원리).

---

## 6. CAP & 선형성 — 분산 일관성의 큰 그림

**CAP의 정확한 의미** ("셋 중 둘"은 오해를 부르는 요약):
- **C = 선형성(Linearizability)** "방금 쓴 최신값을 모두가 본다". ⚠️ **ACID의 C와 무관**.
- **A = 가용성** 죽지 않은 노드는 (에러 아닌) 응답을 준다.
- **P = 파티션 내성** 네트워크 단절에도 동작.

> 파티션(P)은 **현실이라 필수** → 진짜 선택은 **"파티션 중 C냐 A냐"**.

| | CP (일관성 우선) | AP (가용성 우선) |
|---|---|---|
| 파티션 때 | 소수파 **응답 거부** | 일단 응답(오래됐을 수도) |
| 예시 | **ZooKeeper, etcd, HBase** | **Cassandra, DynamoDB, Eureka** |
| 적합 | 락·리더선출·잔액 | 장바구니·피드·좋아요 수 |

→ 앞서 ZK/etcd가 "과반 못 쥐면 쓰기 거부"한 게 곧 **CP의 정의**. ("CA"는 분산에선 무의미 — 단일 노드 가정.)

### 선형성 vs 직렬성 (두 주제가 만나는 지점)
| | **직렬성 Serializability** | **선형성 Linearizability** |
|---|---|---|
| 출신 | DB 트랜잭션 격리 | 분산 일관성 |
| 대상 | 여러 객체·여러 트랜잭션 | **단일 객체** 단일 연산 |
| 보장 | **어떤** 직렬 순서면 OK | 실제 **시간 순서** 존중(최신값 강제) |
| 시간 | 무관(옛 스냅샷 OK) | 존중 |

> 둘 다 만족 = **Strict Serializability**(예: Google Spanner / TrueTime). MVCC SERIALIZABLE 스냅샷은 직렬성은 OK여도 선형성은 아닐 수 있음.

### PACELC (CAP의 실무 확장)
> **if (P)artition → A vs C, **E**lse(평소) → **L**atency vs **C**onsistency**
- **ZK/etcd, Spanner = PC/EC** — 늘 일관성, 대신 느림.
- **Cassandra/Dynamo = PA/EL** — 늘 빠름·가용성, 대신 **최종 일관성(eventual consistency)**.
- 즉 강한 일관성은 파티션 때 가용성만이 아니라 **평소에도 레이턴시**로 비용을 치른다.

---

## 7. 언제 무엇을 — 한 장 요약

| 상황 | 선택 |
|------|------|
| 단일 자원의 정확성(재고 등) | **DB 원자적 UPDATE / 낙관 락** (가장 간단·안전) |
| 높은 처리량, 효율용(중복 방지), 가끔 깨져도 OK | **Redis 락** |
| 정확성 필수, 리더 선출, 설정·서비스 디스커버리 | **ZK / etcd (+ fencing token)** |

---

## 🔗 참고 자료
- **Martin Kleppmann, "How to do distributed locking"** + **antirez, "Is Redlock safe?"** — 논쟁 양측 원문(같이 읽기)
- **Raft 논문 + raft.github.io 시각화** — 합의를 애니메이션으로
- **ZooKeeper 공식 "Recipes — Locks"** / **etcd `concurrency`(Mutex), lease**
- 『데이터 중심 애플리케이션 설계(DDIA)』 8~9장 — 분산의 문제·합의·선형성(이 노트 전체의 교과서)
- **Brewer "CAP Twelve Years Later"**, **Abadi "PACELC"**

## 🌱 심화 키워드
- **Fencing Token** — 분산 락의 근본 안전장치(자원 단 거부)
- **Quorum / 과반 교집합** — split-brain 방지의 수학적 핵심, `R + W > N`(Dynamo)
- **Linearizability / Strict Serializability** — 선형성, Spanner(TrueTime)
- **ZAB vs Raft vs Paxos** — 합의 알고리즘 계보
- **Eventual Consistency / CRDT / LWW** — AP의 충돌 합치기
- **Redlock 논쟁 / STW GC pause** — 시간 기반 락이 깨지는 현실적 이유

## ❓ 남은 질문 (이어서 팔 것)
1. Cassandra의 `R + W > N`은 어떻게 일관성을 조절하나? (정족수 읽기/쓰기)
2. Spanner는 어떻게 전 지구적 strict serializability를 하나? (TrueTime, 원자시계)
3. Raft에서 리더가 죽는 순간 진행 중이던(커밋 안 된) 쓰기는 어떻게 되나?
4. Redisson watchdog의 단점(무한 연장 좀비 락)은 어떻게 다루나?
