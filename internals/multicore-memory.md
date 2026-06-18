# 멀티코어 CPU 와 가상 메모리

멀티코어 환경에서 가상 메모리, TLB, 캐시, NUMA 가 어떻게 얽히는지 정리.
동시성 비용의 진짜 정체 (락 < 캐시 일관성 트래픽) 를 이해하기 위한 문서.

> 선행 문서:
> - [process-thread-memory.md](./process-thread-memory.md) - 프로세스/스레드/가상 메모리 기초
> - [thread-pool.md](./thread-pool.md) - 스레드 풀과 가상 메모리

---

## 1. 멀티코어 하드웨어 구조

```
┌──────────────────────────────────────────────────────────┐
│                        CPU 패키지                          │
│                                                          │
│ ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│ │ Core 0   │  │ Core 1   │  │ Core 2   │  │ Core 3   │   │
│ │          │  │          │  │          │  │          │   │
│ │ Registers│  │ Registers│  │ Registers│  │ Registers│   │
│ │ MMU+TLB  │  │ MMU+TLB  │  │ MMU+TLB  │  │ MMU+TLB  │   │
│ │ L1 cache │  │ L1 cache │  │ L1 cache │  │ L1 cache │   │
│ │ L2 cache │  │ L2 cache │  │ L2 cache │  │ L2 cache │   │
│ └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘   │
│      └─────────────┴─────────────┴─────────────┘         │
│                         │                                │
│              ┌──────────┴──────────┐                     │
│              │   L3 cache (공유)    │                     │
│              └──────────┬──────────┘                     │
└─────────────────────────┼────────────────────────────────┘
                          ↓
                  ┌───────────────┐
                  │ 메인 메모리 (RAM)│
                  │  - 페이지 테이블 │
                  │  - Heap/Stack 등│
                  └───────────────┘
```

### 코어마다 가진 것
- **레지스터** (PC, 범용 레지스터 등)
- **MMU + TLB** (가상→물리 변환 캐시)
- **L1, L2 캐시** (코어 전용)

### 공유 자원
- **L3 캐시**
- **RAM** (페이지 테이블 포함)

### 접근 속도 대략
| 영역 | 지연 시간 |
|------|----------|
| L1 cache | ~1 ns |
| L2 cache | ~3-10 ns |
| L3 cache | ~10-20 ns |
| RAM | ~100 ns |
| NUMA 원격 RAM | ~300 ns+ |
| SSD | ~100 μs |

---

## 2. 가상 주소 공간은 프로세스 단위 (코어와 무관)

> **핵심: 가상 주소 공간과 페이지 테이블은 프로세스에 귀속. 코어가 몇 개든 상관없다.**

```
프로세스 A 의 페이지 테이블 (RAM 에 1개 존재)
            ↑
   ┌────────┼────────┐
   │        │        │
[Core 0] [Core 1] [Core 2]   ← 모두 같은 페이지 테이블 참조
   │        │        │
스레드 T1  스레드 T2  스레드 T3
(프로세스 A) (프로세스 A) (프로세스 A)
```

스레드 T1, T2, T3 가 각각 다른 코어에서 동시에 실행되어도:
- **모두 같은 가상 주소 공간**
- **같은 페이지 테이블** 참조
- Heap 의 `0x7f3a1000` 은 어느 코어에서 보든 같은 물리 위치

---

## 3. TLB 와 TLB Shootdown

### TLB 는 코어마다 따로

같은 가상 주소를 처음 접근하면 각 코어에서 따로따로 TLB 미스가 난다.

```
Core 0: 가상주소 0x1000 접근 → TLB 미스 → 페이지 테이블 조회 → TLB 캐싱
Core 1: 가상주소 0x1000 접근 → TLB 미스 → 페이지 테이블 조회 → TLB 캐싱
Core 2: 가상주소 0x1000 접근 → TLB 미스 → 페이지 테이블 조회 → TLB 캐싱
```

OS 가 페이지 테이블을 안 바꾸는 한, 결과 매핑은 같으니 문제 없음.

### TLB Shootdown (가상 메모리 관련 가장 비싼 작업)

OS 가 **페이지 테이블을 변경**하면 (페이지 해제, 매핑 변경 등) 모든 코어의 TLB 에 있는 오래된 엔트리를 무효화해야 함.

```
Core 0 가 페이지 매핑 변경
   ↓
다른 코어들에게 IPI (Inter-Processor Interrupt) 전송
   ↓
Core 1, 2, 3 각자 자기 TLB 의 해당 엔트리 무효화
   ↓
모든 코어가 다시 페이지 테이블에서 새로 캐싱
```

### 언제 발생?
- `munmap()` 호출
- 페이지 권한 변경 (`mprotect()`)
- 메모리 해제 (`free()` 가 큰 경우)
- JVM GC 가 큰 영역 해제 (특히 G1, ZGC)
- 컨테이너 메모리 회수

→ 멀티코어가 많을수록 IPI 대상이 많아져서 더 비싸짐.

---

## 4. 진짜 문제: 캐시 일관성 (Cache Coherence)

가상 주소 공간보다 **CPU 캐시**가 멀티코어에서 더 큰 이슈.

### 시나리오

```java
int counter = 0;  // Heap 에 있음

// Core 0 의 스레드 T1
counter++;        // counter 를 자기 L1 캐시에 로드해서 증가

// Core 1 의 스레드 T2
counter++;        // counter 를 자기 L1 캐시에 로드해서 증가
```

각 코어의 L1 캐시에 **counter 의 사본이 따로** 있으면:

```
Core 0 L1: counter = 1 (자기가 증가시킴)
Core 1 L1: counter = 1 (자기도 증가시킴)
RAM:       counter = 0 (아직 안 씀)
```

→ 둘 다 1로 끝나고 RAM 에 쓰면 최종 1. **두 번 증가했는데 결과는 1.**
이게 race condition 의 하드웨어적 실체.

### MESI 프로토콜

이걸 막기 위해 CPU 들은 **캐시 일관성 프로토콜** (대표적으로 MESI) 로 통신.

| 상태 | 의미 |
|------|------|
| **M** (Modified) | 이 코어만 갖고 있고, RAM 과 다름 (dirty) |
| **E** (Exclusive) | 이 코어만 갖고 있고, RAM 과 같음 |
| **S** (Shared) | 여러 코어가 공유 중 |
| **I** (Invalid) | 무효 (다른 코어가 수정함) |

### MESI 동작 예시

```
초기: counter = 0, RAM 에만 있음

[1] Core 0 이 counter 읽음
    Core 0 L1: counter=0 (E)
    
[2] Core 1 도 counter 읽음
    Core 0 L1: counter=0 (S)  ← Exclusive → Shared
    Core 1 L1: counter=0 (S)

[3] Core 0 이 counter++ 수행
    Core 0: "invalidate" 신호 브로드캐스트
    Core 0 L1: counter=1 (M)
    Core 1 L1: counter=0 (I) ← 무효화됨

[4] Core 1 이 counter 읽으려 함
    Core 1 L1 은 Invalid 상태
    → Core 0 의 캐시 또는 RAM 에서 다시 가져옴 (느림)
    Core 0 L1: counter=1 (S)
    Core 1 L1: counter=1 (S)
```

### 비용
- 코어 간 invalidate 신호 = 캐시 일관성 트래픽
- 공유 변수에 자주 쓰면 → 캐시 라인이 핑퐁
- **락 자체보다 이 트래픽이 더 비쌀 때가 많음**

---

## 5. False Sharing (멀티코어의 함정)

가상 메모리 상에서는 **다른 변수**인데, 같은 **캐시 라인 (보통 64 바이트)** 에 있으면 캐시 일관성 비용이 발생.

### 문제 코드

```java
class Counter {
    long a;  // 8 bytes
    long b;  // 8 bytes
    // a 와 b 가 같은 64바이트 캐시 라인에 들어감
}

// Core 0 의 T1: counter.a++ 만 함
// Core 1 의 T2: counter.b++ 만 함
```

논리적으로는 독립이지만, **같은 캐시 라인을 공유**하기 때문에:

```
T1 이 a 수정
  → 그 캐시 라인 전체가 Modified
  → Core 1 의 b 사본도 Invalidate 됨
  → T2 가 b 읽으려면 다시 가져와야 함

T2 가 b 수정
  → 그 캐시 라인 전체가 Modified
  → Core 0 의 a 사본도 Invalidate 됨
  → T1 이 a 읽으려면 다시 가져와야 함

→ 무한 핑퐁
```

논리적으로 독립인데 마치 같은 변수 경쟁하는 것처럼 느려진다.

### 해결: 패딩

```java
// JVM 어노테이션 (Java 8+)
@jdk.internal.vm.annotation.Contended
class Counter {
    long a;
    long b;
}

// 수동 패딩
class Counter {
    long a;
    long pad1, pad2, pad3, pad4, pad5, pad6, pad7;  // 56 bytes
    long b;
}
```

`-XX:-RestrictContended` 옵션 필요할 수 있음.

### 실무에서 자주 보는 false sharing
- `LongAdder` (Java) 가 내부적으로 패딩 사용
- 고성능 큐 (Disruptor) 가 false sharing 회피 핵심
- 통계 카운터 배열 (코어별 counter[i]) 시 주의

---

## 6. NUMA (Non-Uniform Memory Access)

코어가 많아지면 (서버급), RAM 도 여러 뱅크로 나뉜다.

```
┌──────────────┐         ┌──────────────┐
│ NUMA Node 0  │         │ NUMA Node 1  │
│              │         │              │
│ Cores 0-7    │ ←─────→ │ Cores 8-15   │
│ Local RAM    │  interconnect          │
│              │         │ Local RAM    │
└──────────────┘         └──────────────┘
```

- 자기 노드 RAM 접근: 빠름 (~100ns)
- 다른 노드 RAM 접근: 느림 (~300ns 이상)

### 문제 상황

같은 프로세스의 스레드가 노드 0, 1 에 흩어져 있고, Heap 객체가 노드 0 의 RAM 에 있으면:
- 노드 1 의 스레드가 그 객체 접근 시 느림

### 해결 도구
- **NUMA-aware 배치**: 가능하면 같은 노드 안에서 스레드 + 데이터 묶기
- **`numactl`**: 프로세스를 특정 노드에 핀
  ```bash
  numactl --cpunodebind=0 --membind=0 java -jar app.jar
  ```
- **`taskset`**: CPU 코어에 핀
- **JVM 옵션**: `-XX:+UseNUMA` (G1, Parallel GC 에서 효과)

### 확인 명령어
```bash
$ numactl --hardware       # NUMA 노드 구조 확인
$ numastat -p <PID>        # 프로세스의 노드별 메모리 사용량
```

---

## 7. Memory Visibility 와 `volatile`

가상 주소 상으로 같은 변수여도, **다른 코어의 캐시에 갇혀있으면 못 본다.**

### 문제 코드

```java
class Worker {
    boolean running = true;  // Heap

    void stop() {
        running = false;  // Core 0 에서 호출
    }

    void work() {
        while (running) {  // Core 1 에서 실행
            // ... 영원히 안 멈출 수도 있음
        }
    }
}
```

Core 1 이 `running` 을 자기 L1 캐시에 갖고 있고 갱신을 안 받으면, Core 0 이 false 로 바꿔도 못 본다. (실제로는 JIT 컴파일러 최적화도 같이 작용)

### 해결: `volatile`

```java
volatile boolean running = true;  // 가시성 보장
```

`volatile` 은 컴파일러/CPU 에게:
- "매번 메모리에서 읽어라" (캐시 사본 신뢰 X)
- "쓰기는 즉시 메모리에 반영해라"
- "이 변수 주변에 reordering 금지" (메모리 배리어)

### 더 강한 동기화
- `synchronized`: 락 + 메모리 배리어 + 가시성
- `AtomicXxx`: CAS 기반 lock-free 동기화 + 가시성
- `java.util.concurrent` 컬렉션: 내부적으로 가시성 보장

---

## 8. 스레드 풀과 멀티코어의 연결

앞서 본 스레드 풀 + 가상 메모리 논의에 멀티코어를 더하면:

```
풀의 스레드가 여러 코어에 흩어져 실행
   ↓
같은 Heap (공유 가상 주소) 의 객체 접근
   ↓
각 코어의 L1/L2 캐시에 사본 만들어짐
   ↓
공유 변수 수정 시 캐시 일관성 트래픽 발생
   ↓
풀 크기 ↑ + 공유 데이터 ↑ → 캐시 일관성 비용 폭증
```

### 풀 사이즈 공식의 진짜 이유

> "스레드 풀 크기 = 가용 CPU 코어 × N" 공식이 의미가 있는 이유.

코어보다 많은 스레드는:
- 컨텍스트 스위칭 오버헤드 누적
- 캐시 라인 경쟁 증가
- TLB pressure 증가
- L1/L2 캐시 hit rate 감소 (스레드 전환 시 다른 데이터 로드)

### CPU-bound vs I/O-bound

| 작업 유형 | 권장 풀 크기 |
|----------|-------------|
| CPU-bound | 코어 수 ~ 코어 수 + 1 |
| I/O-bound | 코어 수 × (1 + W/C), W=대기시간, C=계산시간 |

I/O bound 가 더 큰 이유: 대부분 시간을 blocking 으로 보내서 캐시 경쟁이 적음.

---

## 9. 멀티코어가 더하는 새 문제들 한눈에

| 문제 | 원인 | 해결 |
|------|------|------|
| **TLB Shootdown** | 페이지 테이블 변경 시 모든 코어 TLB 동기화 | 페이지 매핑 변경 최소화 |
| **Cache Coherence 비용** | 공유 변수 수정 시 코어 간 invalidate | 공유 최소화, 락 신중히 |
| **False Sharing** | 다른 변수가 같은 캐시 라인 | 패딩, `@Contended` |
| **NUMA latency** | 원격 노드 RAM 접근 | NUMA-aware 배치, `numactl` |
| **Memory Visibility** | 코어별 캐시에 변경이 안 보임 | `volatile`, `synchronized`, atomic |

---

## 10. 계층 정리

```
가상 주소 공간 = 프로세스 단위 (코어 수와 무관)
   ↓
페이지 테이블 = 프로세스마다 1개 (RAM 에 있음)
   ↓
TLB = 코어마다 따로 (페이지 테이블의 코어별 캐시)
   ↓
L1/L2 캐시 = 코어마다 따로 → 캐시 일관성 문제 발생
   ↓
L3 캐시, RAM = 공유
   ↓
NUMA 노드 = (대규모 시) RAM 도 노드별 분리
```

---

## 한 줄 요약

> **멀티코어에서도 가상 주소 공간은 프로세스 단위로 그대로다 (코어와 무관).**
> 다만 TLB, L1/L2 캐시가 코어마다 따로라서 **TLB Shootdown / Cache Coherence / False Sharing / NUMA / Memory Visibility** 라는 새로운 비용들이 추가된다.
> 동시성 코드의 진짜 비싼 부분은 락 자체가 아니라 이 캐시 일관성 트래픽인 경우가 많다.

### 실무 체크리스트
- [ ] 공유 변수를 최소화하고 있는가? (스레드 로컬 우선)
- [ ] 핫한 카운터에 false sharing 가능성은 없는가? (`LongAdder` 검토)
- [ ] 가시성이 필요한 플래그에 `volatile` 을 썼는가?
- [ ] 풀 크기를 CPU 코어 수 기반으로 설정했는가?
- [ ] NUMA 환경이면 `numactl` 핀닝을 검토했는가?
- [ ] GC 로그에 TLB shootdown 관련 stall 이 없는가?
