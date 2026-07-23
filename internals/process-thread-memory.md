# 프로세스, 스레드, 가상 메모리

OS 메모리 관리 전반 정리. 프로세스/스레드 메모리 구조부터 시작해서 가상 주소 공간, 페이징, Demand Paging, Virtual Memory 까지.

> 관련 문서:
> - [process-thread-basics.md](./process-thread-basics.md) - 프로세스와 스레드의 기초 개념 (힙, 스택, 작업/실행 흐름 차이)
> - [thread-pool.md](./thread-pool.md) - 스레드 풀 운영과 가상 메모리 관점
> - [multicore-memory.md](./multicore-memory.md) - 멀티코어 CPU 에서의 가상 메모리, 캐시 일관성, NUMA
> - [jvm-heap-metaspace.md](./jvm-heap-metaspace.md) - JVM Heap, Metaspace, Klass 와 실행 흐름
> - [context-switching.md](./context-switching.md) - 컨텍스트 스위칭 (TLB flush·주소공간 교체가 프로세스 전환을 비싸게 하는 이유)

---

## 목차

- **[1. 프로세스 메모리 구조](#1-프로세스-메모리-구조)** — Text / Data / BSS / Heap / Stack 영역
- **[2. 스레드와 메모리](#2-스레드와-메모리)** — 공유 영역 vs 독립 영역, 동기화 필요성
- **[3. 가상 주소 공간 (Virtual Address Space)](#3-가상-주소-공간-virtual-address-space)** — 프로세스 격리, 페이지 테이블
- **[4. 페이징 (Paging)](#4-페이징-paging)** — 가상↔물리 매핑, MMU, TLB
- **[5. Demand Paging (요구 페이징)](#5-demand-paging-요구-페이징)** — lazy 로딩, Page Fault (Minor/Major)
  - [메모리 계층](#메모리-계층--cpu-부터-ssd-까지) (CPU 캐시 → RAM → SSD swap)
  - [가상 주소 접근 전체 흐름](#가상-주소-접근의-전체-흐름) (PTE → Page Fault → OS)
  - ["찾는다" 가 아니라 "직접 lookup"](#찾는다-가-아니라-직접-lookup)
  - [JVM 시사점](#jvm-시사점) (GC 와 Major Fault)
- **[6. Page Replacement (페이지 교체)](#6-page-replacement-페이지-교체)** — FIFO, LRU, LFU, Clock
- **[7. Thrashing (쓰래싱)](#7-thrashing-쓰래싱)** — RAM 부족 증상과 해결
- **[8. Virtual Memory 전체 정리](#8-virtual-memory-전체-정리)** — 메커니즘 통합 + 용어 정리
- **[9. 자바/JVM 관점](#9-자바jvm-관점)**
  - [Process Heap vs Java Heap](#process-heap-vs-java-heap--같은-이름-다른-영역) (같은 이름, 다른 영역)
  - [JVM Heap 과 Demand Paging](#jvm-heap-과-demand-paging)
  - [`-XX:+AlwaysPreTouch`](#-xxalwayspretouch)
  - [`ThreadLocal` 과 TLS](#threadlocal-과-tls)
- **[10. 한 줄 요약](#10-한-줄-요약)** — 학습 순서 포함

---

## 1. 프로세스 메모리 구조

프로세스 하나는 다음 영역들로 구성된 메모리 공간을 가진다.

```
높은 주소 ┌─────────────┐
         │   Stack     │  ↓ (아래로 자람)
         │             │
         │   <empty>   │  ↕ (Stack 과 Heap 사이 빈 공간)
         │             │
         │   Heap      │  ↑ (위로 자람)
         ├─────────────┤
         │   BSS       │  초기화 안 된 전역/static
         ├─────────────┤
         │   Data      │  초기화된 전역/static
         ├─────────────┤
         │   Text      │  실행 코드 (기계어)
낮은 주소 └─────────────┘
```

| 영역 | 내용 | 특징 |
|------|------|------|
| **Text (Code)** | 컴파일된 기계어 | 읽기 전용, 공유 가능 |
| **Data** | 초기화된 전역/static | 프로그램 시작 시 초기화 |
| **BSS** | 초기화 안 된 전역/static | 0 으로 초기화 |
| **Heap** | `malloc` 동적 할당 (`brk`/`sbrk` 영역) | 개발자가 `free` 로 관리 |
| **Stack** | 함수 호출 시 지역변수/리턴주소 | LIFO, 자동 할당/해제, 1~8MB 제한 |

> ⚠️ 위의 "Heap" 은 **전통적 Process Heap** (= Native Heap, malloc 영역, `brk/sbrk` 로 늘리는 곳).
> Java 의 `new` 가 객체를 할당하는 **Java Heap (JVM Heap)** 은 이와 **별개의 영역**이고, JVM 이 `mmap` 으로 따로 받아 GC 로 관리한다.
> 같은 프로세스의 가상 주소 공간 안에 **두 종류의 "Heap" 이 자매 영역으로 공존**한다. 자세한 건 [jvm-heap-metaspace.md](./jvm-heap-metaspace.md) 1장 참조.

---

## 2. 스레드와 메모리

스레드는 프로세스 안의 실행 흐름 단위. **공유하는 것**과 **독립적인 것**이 나뉜다.

```
[Process Memory]
┌─────────────────────────────────────────┐
│                                         │
│  ┌───────────────────────────────────┐  │
│  │  Text │ Data │ BSS │   Heap       │  │  ← 모든 스레드 공유
│  └───────────────────────────────────┘  │
│                                         │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  │
│  │ Stack 1 │  │ Stack 2 │  │ Stack 3 │  │  ← 스레드별 독립
│  │ (T1)    │  │ (T2)    │  │ (T3)    │  │
│  └─────────┘  └─────────┘  └─────────┘  │
└─────────────────────────────────────────┘
```

### 공유 영역 (프로세스 단위)
- **Text**: 같은 코드를 실행
- **Data / BSS**: 전역변수, static 변수
- **Heap**: 동적 할당 메모리 → 그래서 **동기화 (mutex, lock)** 필요
- 파일 디스크립터, 소켓 등 OS 자원도 공유

### 스레드별 독립 영역
- **Stack**: 각자의 함수 호출 흐름
- **레지스터 / PC (Program Counter)**: 각자 어디까지 실행했는지
- **TLS (Thread Local Storage)**: 스레드 전용 변수 (`ThreadLocal`, `thread_local`)

### 프로세스 vs 스레드 핵심 차이

| 항목 | 프로세스 | 스레드 |
|------|---------|--------|
| 메모리 공간 | 통째로 따로 (격리) | 공유 (Heap/Data) + Stack 만 따로 |
| 통신 비용 | 비쌈 (IPC 필요) | 쌈 (변수 공유) |
| 컨텍스트 스위칭 | 비쌈 (TLB flush) | 쌈 |
| 안전성 | 강함 | 약함 (race condition 위험) |

### 왜 멀티스레드에서 동기화가 필요한가?

```java
class Counter {
    int count = 0;          // Heap 에 있음 → 모든 스레드가 공유
    void increment() {
        count++;            // 읽기 → 더하기 → 쓰기 (원자적이지 않음)
    }                       // 동시 호출 시 race condition 발생
}
```

→ Heap 공유 때문. Stack 의 지역변수는 race condition 안 일어남.

---

## 3. 가상 주소 공간 (Virtual Address Space)

> **각 프로세스가 "마치 자기가 메모리를 통째로 독점하는 것처럼" 느끼게 해주는 가짜 주소 공간.**

실제 RAM 과 직접 연결되어 있지 않고, **MMU (Memory Management Unit)** 가 가상 주소 → 물리 주소로 매핑한다.

```
[Process A's view]                    [Real RAM]
┌─────────────────┐                 ┌─────────────┐
│ 0xFFFFFFFF      │                 │             │
│   Stack         │ ─────┐          │             │
│   ...           │      │          │             │
│   Heap          │ ──┐  └────────► │  somewhere  │
│   Data          │   │             │  in RAM     │
│   Text          │   └───────────► │             │
│ 0x00000000      │                 │             │
└─────────────────┘                 └─────────────┘
   (가상 주소)                        (물리 주소)
```

### 왜 만들었나?

1. **프로세스 격리**: A 의 `0x1000` 과 B 의 `0x1000` 은 물리적으로 다른 곳. 함부로 못 건드림.
2. **메모리 단편화 해결**: 물리적으로 흩어져 있어도 가상 주소상 연속처럼 보임.
3. **물리 RAM 보다 큰 공간 사용**: 64bit OS 는 이론상 2^64 바이트. 안 쓰는 페이지는 디스크로 swap.
4. **같은 코드 공유**: `libc` 같은 라이브러리를 한 번만 RAM 에 올리고 여러 프로세스가 같은 물리 페이지를 가리키게 함.

### 프로세스 vs 스레드 in 가상 주소 공간

```
프로세스 A 가상공간         프로세스 B 가상공간
┌────────────┐             ┌────────────┐
│ Stack      │             │ Stack      │
│ Heap       │             │ Heap       │
│ Data       │             │ Data       │
│ Text       │             │ Text       │
└────────────┘             └────────────┘
   각자 따로                  각자 따로

            프로세스 가상 주소 공간 1개
┌─────────────────────────────────────────┐
│  Text │ Data │ BSS │      Heap          │ ← 공유
├─────────────────────────────────────────┤
│ Stack(T1) │ Stack(T2) │ Stack(T3)       │ ← 영역만 다름
└─────────────────────────────────────────┘
   스레드끼리는 같은 가상 주소 공간 공유
```

**핵심**: 스레드는 **같은 페이지 테이블을 공유**한다.
- T1 이 만든 객체의 주소 `0x7f3a1000` 을 T2 가 그대로 받아 접근 가능 → 빠른 통신
- 동시에 race condition 의 원인

### 스택도 가상 주소 위에 있다

```
프로세스 가상 주소 공간 (예: 0x0000... ~ 0xFFFF...)

0xFFFF... ┌──────────────┐
          │  Stack T1    │  ← 0x7FFF_F000 근처
          ├──────────────┤
          │  Stack T2    │  ← 0x7FFE_F000 근처
          ├──────────────┤
          │  Stack T3    │  ← 0x7FFD_F000 근처
          │              │
          │   <empty>    │
          │              │
          │  Heap        │  ← 0x0060_0000 근처부터 위로
          ├──────────────┤
          │  BSS         │
          ├──────────────┤
          │  Data        │
          ├──────────────┤
          │  Text        │  ← 0x0040_0000 근처
0x0000... └──────────────┘
```

스레드의 Stack 도 결국 **같은 가상 주소 공간 안의 다른 위치**일 뿐.

---

## 4. 페이징 (Paging)

가상 주소를 물리 주소로 변환하는 **메커니즘**.

### 페이지 vs 프레임

- **페이지 (Page)**: 가상 주소 공간을 일정 크기로 자른 단위 (보통 4KB)
- **프레임 (Frame)**: 물리 RAM 을 같은 크기로 자른 단위 (4KB)
- **페이지 테이블**: "이 페이지는 어느 프레임에 매핑되어 있는지" 기록한 표

### 가상↔물리 매핑 예시

```
[Virtual Address Space — looks contiguous]
┌─────────────────────────────────────┐
│  Heap                               │
│  ┌────┬────┬────┬────┬────┬────┐   │
│  │ P1 │ P2 │ P3 │ P4 │ P5 │ P6 │   │  ← 가상 페이지
│  └────┴────┴────┴────┴────┴────┘   │
└─────────────────────────────────────┘
      ↓ 페이지 테이블 매핑
[Physical RAM — frames]
┌─────────────────────────────────────────────┐
│                                             │
│  ┌────┐    ┌────┐  ┌────┐                   │
│  │ P3 │... │ P1 │..│ P5 │ ...               │
│  └────┘    └────┘  └────┘                   │
│        ┌────┐    ┌────┐         ┌────┐      │
│  ...   │ P6 │... │ P2 │   ...   │ P4 │      │
│        └────┘    └────┘         └────┘      │
└─────────────────────────────────────────────┘
       물리적으로는 완전히 흩어져 있음!
```

페이지 테이블:
```
가상 페이지 → 물리 프레임
   P1     →     0x8A000
   P2     →     0x3C000
   P3     →     0x1F000
   ...
```

### 왜 페이징인가?

1. **메모리 단편화 해결**: 연속된 큰 공간이 없어도 페이지 단위로 흩뿌려서 사용 가능
2. **Swap 가능**: 자주 안 쓰는 페이지는 디스크로 보내고, 필요할 때 다시 RAM 으로
3. **공유 페이지**: 같은 라이브러리를 여러 프로세스가 같은 프레임으로 매핑
4. **Copy-on-Write (COW)**: `fork()` 시 처음엔 부모와 같은 프레임 공유, 쓰기 시점에만 복사

### TLB (Translation Lookaside Buffer)

매번 페이지 테이블을 메모리에서 조회하면 느림 → CPU 안에 캐시를 둠.

```
[CPU] → "가상주소 0x1000 어디야?"
         ↓
       [TLB 캐시 확인] ─ HIT  → 즉시 물리주소 반환
              ↓ MISS
         [페이지 테이블 조회] (느림)
              ↓
         [TLB 에 캐싱]
```

- **프로세스 전환 시 TLB flush** → 느림
- **스레드 전환은 같은 페이지 테이블** → TLB 유효 → 빠름

---

## 5. Demand Paging (요구 페이징)

> **"필요할 때까지 페이지를 RAM 에 안 올린다"** 는 전략.
> 프로그램이 실제로 해당 메모리에 접근하는 순간에만 디스크에서 RAM 으로 가져온다.

### 왜 필요한가

```
Example: 10MB program
┌─────────────────────────────┐
│  hot functions     (2MB)    │  ← 이것만 있으면 충분
│  error handlers    (1MB)    │  ← 거의 안 쓰임
│  config logic      (0.5MB)  │  ← 시작 시에만 쓰임
│  large constants   (5MB)    │  ← 일부만 쓰임
└─────────────────────────────┘

전체를 RAM 에 올리면 → 10MB 낭비
필요한 것만 올리면 → 2MB 면 충분
```

### 동작 흐름

```
[1] 프로그램 시작
     ↓ 페이지 테이블은 만들지만 대부분 "RAM 에 없음" 표시

[2] CPU 가 가상주소 0x1000 접근 시도
     ↓
[3] MMU 가 페이지 테이블 확인
     ↓
     ├─ "RAM 에 있음" → 정상 접근 (HIT)
     │
     └─ "RAM 에 없음" → Page Fault 발생!
             ↓
[4] OS 의 Page Fault Handler 동작
     ↓
     ├─ 디스크에서 해당 페이지 로드
     ├─ 빈 프레임 찾아서 배치
     ├─ 페이지 테이블 업데이트
     └─ 멈췄던 명령어 다시 실행
```

### Page Fault 의 두 종류

| 종류 | 설명 | 비용 |
|------|------|------|
| **Minor Fault** | 페이지가 이미 RAM 어딘가에 있는데, 현재 프로세스의 페이지 테이블에만 매핑이 안 된 경우 (공유 라이브러리, COW 후 첫 접근) | 빠름 |
| **Major Fault** | 페이지가 진짜로 RAM 에 없어서 디스크에서 읽어와야 하는 경우 | 느림 (μs → ms) |

```bash
# 리눅스에서 확인
$ ps -o min_flt,maj_flt,cmd -p <PID>
```

### Lazy Loading 과의 유사성

```java
// 비슷한 개념 - 필요할 때 초기화
private List<Item> items;
public List<Item> getItems() {
    if (items == null) {
        items = loadFromDB();  // 실제 호출 시점에 로드
    }
    return items;
}
```

OS 의 Demand Paging 도 결국 같은 lazy loading 패턴.

### 메모리 계층 — CPU 부터 SSD 까지

CPU 는 **RAM 만 본다.** SSD 의 데이터는 반드시 RAM 으로 한 번 들어와야 처리 가능.

```
CPU
 ├─ 레지스터
 ├─ L1/L2/L3 캐시 (CPU 내장)
 └─ RAM (메인 메모리)        ← 여기까지만 직접 접근

SSD/HDD                       ← CPU 직접 접근 불가, OS 가 RAM 으로 로드
```

각 계층의 속도:

```
Level                Latency        Size           Who manages
──────────────────────────────────────────────────────────────
CPU 레지스터          ~0.3ns         ~bytes         컴파일러
L1 cache             1ns            32KB           HW 자동
L2 cache             3-10ns         256KB-1MB      HW 자동
L3 cache             10-40ns        8-32MB         HW 자동
RAM (DRAM)           50-100ns       ~GB            OS (Page Table)
SSD swap             10-100μs       ~TB            OS (Page Fault)
HDD swap             5-15ms         ~TB            OS (Page Fault)
```

RAM → SSD swap = **100~1000 배 느림.** swap 한 번 갔다 오는 시간에 cache hit 천 번 가능.

### 가상 주소 접근의 전체 흐름

```
[1] CPU: "가상 주소 0x7f1000 읽어줘"
        ↓
[2] MMU + TLB 가 가상→물리 변환
        ├─ TLB hit  → 즉시 (~1ns)
        └─ TLB miss → 페이지 테이블 walk (~100ns)
        ↓
[3] PTE 확인
        ├─ present bit = 1 → 물리 주소 얻음 → RAM 접근
        └─ present bit = 0 → Page Fault! OS 호출
        ↓
[4] OS 가 PTE 의 다른 비트 확인
        "이 페이지가 어디 있나?"
        ├─ Anonymous + 처음 접근 → 빈 RAM 프레임 할당 (zero page)
        ├─ Swap 에 있음         → SSD 에서 읽어와 RAM 으로
        ├─ 파일 매핑            → 파일에서 읽어와 RAM 으로
        └─ 잘못된 접근          → SIGSEGV
        ↓
[5] RAM 로드 → PTE 업데이트 → 명령어 재시도
```

### "찾는다" 가 아니라 "직접 lookup"

OS 는 **검색하지 않는다.** PTE 가 모든 위치 정보를 들고 있음.

```
PTE 안의 비트들:
  present     : RAM 에 있나?
  swap slot   : swap 의 어느 위치에 있나? (있다면)
  file offset : 파일의 어느 위치에 있나? (file-backed 인 경우)
  dirty       : 수정됐나?
  accessed   : 최근 접근됐나? (LRU 알고리즘 용)
```

```
잘못된 이해: "RAM 에서 찾고, 없으면 SSD 뒤지고..."
                ↓ (탐색 느낌)

실제 동작:  "Page Table 이 위치를 알려준다. 직접 가서 가져온다."
                ↓ (direct lookup)
```

### JVM 시사점

```
JVM 객체 접근:
  ├─ 자주 쓰는 객체     → CPU 캐시 / RAM 에 hot
  ├─ Old Gen 의 객체    → RAM 에 있지만 cache miss 빈번
  └─ Swap 으로 밀려난 페이지 → Major Fault → SSD 에서 읽기 (매우 느림)
```

GC 가 갑자기 stop-the-world 길어지는 흔한 원인:
- GC 가 안 쓰던 Old Gen 페이지 건드림
- 그 페이지가 이미 swap 으로 밀려나 있음
- Major Fault 폭증 → GC 느려짐

`-XX:+AlwaysPreTouch` 는 시작 시 전부 RAM 으로 끌어와 이 현상 예방. RAM 충분한 환경에서만 의미. 자세한 건 [jvm-heap-metaspace.md](./jvm-heap-metaspace.md) 2.4 참조.

---

## 6. Page Replacement (페이지 교체)

RAM 이 꽉 차면, 어떤 페이지를 디스크로 내보낼지 결정해야 한다.

| 알고리즘 | 동작 | 특징 |
|---------|------|------|
| **FIFO** | 가장 먼저 들어온 페이지 교체 | 단순, 자주 쓰는 페이지도 쫓겨남 |
| **LRU** (Least Recently Used) | 가장 오래 안 쓴 페이지 교체 | 실무 가장 흔함, 구현 비용 있음 |
| **LFU** (Least Frequently Used) | 가장 적게 쓰인 페이지 교체 | 빈도 기반 |
| **Clock** | LRU 근사 알고리즘 | 실제 OS 가 자주 씀 |

---

## 7. Thrashing (쓰래싱)

> RAM 이 너무 부족해서 **페이지 교체만 반복**하며 실제 작업은 거의 못 하는 상황.

```
정상:   [작업][작업][교체][작업][작업][교체][작업]...
쓰래싱: [교체][교체][작업][교체][교체][교체][작업]... ← 거의 일 안 함
```

### 증상
- CPU 사용률은 낮은데 디스크 I/O 가 미친 듯이 발생
- 응답 속도 급락
- Major Fault 폭증

### 해결책
- RAM 증설
- 동시 실행 프로세스 줄이기
- 워킹셋 (Working Set) 관리

---

## 8. Virtual Memory 전체 정리

> **Virtual Memory = "프로세스에게 큰 메모리가 있는 것처럼 보여주자" 라는 큰 개념.**
> 이를 실현하기 위한 여러 메커니즘의 묶음.

```
[Virtual Memory — concept / goal]

  "각 프로세스에게 크고 연속된 자기만의 메모리 환상을 준다"
  (Each process gets the illusion of large contiguous memory of its own)

        ↑ 이걸 실현하기 위한 메커니즘들 ↓

  1. Virtual Address Space  (가상 주소 공간)
     - 프로세스마다 독립된 주소 체계

  2. Paging  (페이징)
     - 페이지 ↔ 프레임 매핑 (페이지 테이블, MMU, TLB)

  3. Demand Paging  (요구 페이징)
     - 필요할 때만 디스크 → RAM 으로 로드

  4. Page Replacement  (페이지 교체)
     - RAM 꽉 차면 누굴 내보낼지 (LRU, Clock 등)

  5. Swapping
     - 안 쓰는 페이지를 디스크 swap 영역에 보관
```

### 도서관 비유

- 도서관에 가면 **수천만 권의 책이 다 있는 것처럼** 보임 (= 가상 주소 공간)
- 실제로는 인기 책만 1층 서가에 두고 (= RAM), 나머지는 창고에 (= 디스크)
- 누가 요청하면 그때 창고에서 가져옴 (= Demand Paging)
- 1층이 꽉 차면 안 빌려가는 책을 창고로 (= Page Replacement)
- 모든 책에 분류 번호 (= 페이지 테이블)

### 용어 정리

| 용어 | 정체 |
|------|------|
| **Virtual Memory** | **목표/개념** (RAM 한계 넘어 큰 메모리 사용) |
| Virtual Address Space | 그 목표를 위한 **주소 구조** (프로세스 격리 포함) |
| Paging | 가상↔물리 **변환 메커니즘** |
| Demand Paging | 페이징의 **로딩 전략** (lazy) |
| Page Fault | 그 전략 중 발생하는 **이벤트** |
| Page Replacement | RAM 가득 찼을 때 **교체 정책** |
| Swap | 디스크의 **백업 저장소** |
| TLB | 페이지 테이블의 **CPU 캐시** |

### 문맥별 "Virtual Memory" 뉘앙스

- **OS 교과서**: 위에 설명한 큰 개념
- **시스템 관리자**: 보통 swap 공간을 의미
- **`top`/`ps` 의 VIRT 컬럼**: 프로세스가 잡고 있는 **가상 주소 공간 크기**
- **Windows "가상 메모리 설정"**: 페이지 파일 (swap) 크기 설정

```bash
$ top
PID  USER  VIRT    RES    SHR
123  app   8.5G    1.2G   100M
         ↑ 가상   ↑ 실제  ↑ 공유
         (큰 환상) (RAM)  (다른 프로세스와)
```

VIRT 8.5GB 라고 진짜로 RAM 을 그만큼 쓰는 게 아님. **그만큼의 가상 주소를 할당받았다**는 뜻. 실제 RAM 사용량은 RES (Resident Set Size).

---

## 9. 자바/JVM 관점

JVM 도 OS 의 가상 메모리 시스템 위에서 동작.

### Process Heap vs Java Heap — 같은 이름, 다른 영역

위 1장의 "Heap" (= Process Heap, malloc 영역) 과 JVM 의 "Java Heap" 은 **같은 가상 주소 공간 안에 공존하는 별개 영역**이다.

| | Process Heap | Java Heap |
|---|---|---|
| 누가 할당 | `malloc()` (C/C++) | `new` (Java) |
| 영역 확장 방식 | `brk/sbrk` | `mmap` (별도 큰 덩어리) |
| 누가 관리 | 개발자가 `free` | GC |
| JVM 안에서 용도 | 내부 자료구조, JNI, GC 부기 | Java 객체, 배열 |

JVM 은 둘 다 사용한다 — 작은 내부 자료구조는 Process Heap (malloc), Java 객체는 Java Heap (mmap + GC). 자세한 건 [jvm-heap-metaspace.md](./jvm-heap-metaspace.md) 참조.

### JVM Heap 과 Demand Paging

```
JVM 힙을 8GB 로 설정 (-Xmx8g)
   ↓
실제로는 OS 가 demand paging 으로 관리
   ↓
처음엔 일부만 RAM 에 있음
   ↓
GC 가 돌면서 안 쓰던 영역 건드리면 Major Fault 폭발
   ↓
"왜 GC 가 갑자기 느려지지?" 의 원인이 되기도 함
```

### `-XX:+AlwaysPreTouch`
JVM 시작 시 힙 전체에 미리 접근해서 페이지를 RAM 에 올려둠.
- 시작은 느려짐
- 런타임 중 Major Fault 감소
- 운영 환경에서 자주 사용

### `ThreadLocal` 과 TLS
스레드별 독립 영역 (TLS) 의 자바 구현.
- 스레드마다 다른 값을 갖는 변수
- 컨텍스트 전파, 트랜잭션 관리 등에 활용
- 스레드 풀에서 사용 시 메모리 누수 주의 (clear 필수)

---

## 10. 한 줄 요약

> 프로세스는 자기만의 **가상 주소 공간**을 가지고, 그 안에 **Text/Data/BSS/Heap** (공유) 와 **스레드별 Stack** 이 있다.
> 가상 주소는 **페이징**으로 물리 프레임에 매핑되고, **Demand Paging** 으로 필요할 때만 디스크에서 로드된다.
> 이 모든 메커니즘의 묶음이 **Virtual Memory** 이고, 이 덕분에 RAM 보다 큰 프로그램 실행, 프로세스 격리, 메모리 효율이 가능해진다.

### 학습 순서대로 다시 한 줄
**메모리 영역 → 프로세스/스레드 분리 → 가상 주소 공간 → 페이징(페이지/프레임/TLB) → Demand Paging → Page Fault → Page Replacement → Thrashing → Virtual Memory 종합**

---

## ❓ 남은 질문

1. 스택은 스레드별 독립 영역이라는데, 한 스레드가 다른 스레드 스택의 변수에 실제로 접근할 수 있나?

   → **답:** OS/C 레벨에선 가능하다. 스레드들은 같은 가상 주소 공간(같은 페이지 테이블)을 공유하므로 스택 간 하드웨어 격리가 없어, 다른 스레드 스택 주소를 가리키는 포인터는 그대로 역참조된다("독립"은 각자 다른 위치라는 뜻이지 보호막이 아님). 다만 Java 는 지역변수의 주소를 얻을 수단이 없어 언어 차원에서 이 경로가 막혀 있다.
2. 프로세스 전환마다 TLB 를 통째로 flush 하는 게 정말 불가피한가?

   → **답:** 아니다. 현대 x86 은 PCID, ARM64 는 ASID 로 TLB 엔트리에 주소 공간 식별자 태그를 달아, 전환 시 전체 flush 없이 이전 프로세스 엔트리를 보존한다. 그래서 전환 비용이 예전보다 줄었다(그래도 스레드 전환보다는 무겁다).
3. `fork()` 후 COW 로 공유하던 페이지에 자식이 쓰기를 하면 Minor Fault 인가 Major Fault 인가?

   → **답:** Minor Fault 다. 원본 페이지가 이미 RAM 에 있어 복사만 하면 되고 디스크 I/O 가 없기 때문. Major Fault 는 페이지가 swap·파일 등 디스크에 있어 읽어와야 하는 경우로 국한된다.
