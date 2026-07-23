# JVM 메모리 구조: Heap, Metaspace, Klass

일반 (OS) 힙과 JVM 힙의 차이부터 시작해서 Metaspace, Klass, 그리고 실제 프로그램 실행 흐름까지.

> 관련 문서:
> - [process-thread-memory.md](./process-thread-memory.md) - OS 레벨의 프로세스/스레드 메모리 (Heap 은 거기서의 "Heap" 칸)
> - [thread-pool.md](./thread-pool.md) - 스레드와 JVM 메모리
> - [multicore-memory.md](./multicore-memory.md) - 멀티코어와 메모리 가시성

---

## 목차

- **[1. 두 종류의 "힙"](#1-두-종류의-힙)** — Native Heap vs JVM Heap
  - [1.1 Process Heap vs Java Heap — 자매 영역](#11-process-heap-vs-java-heap--자매-영역) (포함관계가 아님)
  - [1.2 `mmap` 이란 무엇인가](#12-mmap-이란-무엇인가) (시그니처, 두 용도, brk 차이, lazy 특성)
  - [1.3 Process Heap 의 본래 목적](#13-process-heap-의-본래-목적) (왜 brk Heap 이 따로 존재하나)
  - [1.4 GC 는 어디에서 작용하는가](#14-gc-는-어디에서-작용하는가--process-heap-에도-gc-가-있나) (Java GC 의 범위, OS Heap 에는 GC 가 있나)
  - [1.5 OS Heap 은 꽉 차지 않나?](#15-os-heap-은-꽉-차지-않나--누수와-관리-그리고-사용자에게-안-보이는-이유) (누수, 관리, 사용자에게 안 보이는 이유)
  - [1.6 JVM Heap 한 줄 정의](#16-jvm-heap-한-줄-정의--멘탈-모델) (멘탈 모델)
- **[2. JVM 프로세스 메모리 전체 그림](#2-jvm-프로세스-메모리-전체-그림)** — 가상 주소 공간 안의 영역들
  - [2.1 영역 간 포함관계](#21-영역-간-포함관계--헷갈리기-쉬운-포인트) (JVM 바이너리 / Java Heap / Native Memory)
  - [2.2 가상 주소 공간의 소유권](#22-가상-주소-공간의-소유권--프로세스-당-1개) (프로세스 당 1개, CPU 코어 당 아님)
  - [2.3 가상 주소 공간의 생성과 소멸](#23-가상-주소-공간의-생성과-소멸) (fork/exec, mm_struct, clone())
  - [2.4 가상 주소 공간의 한계](#24-가상-주소-공간의-한계--무한일까) (CPU 비트 / OS 분할 / 백킹 저장소)
- **[3. Metaspace — PermGen 의 후계자](#3-metaspace--permgen-의-후계자)** — Java 8+ native memory 로 이동
- **[4. Klass — 클래스의 진짜 정체](#4-klass--클래스의-진짜-정체)** — C++ struct, Class 미러와의 구분, klass pointer
- **[5. 프로그램 실행 흐름 — 전체 단계 추적](#5-프로그램-실행-흐름--전체-단계-추적)** — Phase 0 ~ 8
  - [Phase 0: JVM 프로세스 시작](#phase-0-jvm-프로세스-시작)
  - [Phase 1: 부트스트랩](#phase-1-부트스트랩--시스템-클래스-로딩) (시스템 클래스 로딩)
  - [Phase 2: `Hello` 클래스 로딩](#phase-2-hello-클래스-로딩-main-호출-직전)
  - [Phase 3: `main()` 실행 시작](#phase-3-main-실행-시작)
  - [Phase 4: `new Hello("World")`](#phase-4-new-helloworld--객체-탄생-순간) (객체 탄생)
  - [Phase 5: `h.greet()`](#phase-5-hgreet--메서드-디스패치) (메서드 디스패치)
  - [Phase 6: JIT 컴파일](#phase-6-jit-컴파일-반복-호출-시)
  - [Phase 7: GC](#phase-7-gc)
  - [Phase 8: 종료 / ClassLoader unload](#phase-8-종료-또는-classloader-unload)
- **[6. 전체 흐름을 한 장으로](#6-전체-흐름을-한-장으로)** — Stack → Heap → Metaspace → Code Cache 다이어그램
- **[7. 흐름이 보여주는 핵심 인사이트](#7-흐름이-보여주는-핵심-인사이트)** — 5가지 (모든 영역 등장, klass ptr 다리, ...)
- **[8. 영역별 빠른 참조 표](#8-영역별-빠른-참조-표)** — Java Heap, Metaspace, Code Cache, Stack, Direct Buffer, Native Heap
- **[9. 운영 관련 JVM 옵션 빠른 참조](#9-운영-관련-jvm-옵션-빠른-참조)** — `-Xms/-Xmx/-Xss/-XX:MaxMetaspaceSize` 등
- **[10. 한 줄 요약](#10-한-줄-요약)** — 핵심 삼각형 (Heap ↔ Klass ↔ Class 미러)
- **[11. 학습 순서](#11-학습-순서)** — 개념 학습 순서 + 실행 흐름 순서

---

## 1. 두 종류의 "힙"

### Native Heap (= 일반 힙, OS 힙, Process Heap)
- OS 가 프로세스에 주는 동적 할당 영역
- C/C++ 의 `malloc`/`free` 가 다루는 그 힙
- [process-thread-memory.md](./process-thread-memory.md) 의 "Heap" 칸이 바로 이것

### JVM Heap (= Java Heap)
- JVM 이 OS 한테 큰 덩어리를 한 번에 받아서 (`mmap`) **자기가 직접 관리**하는 영역
- `new Foo()` 한 Java 객체가 사는 곳
- **GC** 가 관리 (malloc/free 가 아님)

> 핵심: JVM Heap 은 "관리 방식이 다른 별도 영역" 이다. JVM 입장에서는 native heap 의 malloc 도 따로 쓰고, Java Heap 도 따로 들고 있다.

### 1.1 Process Heap vs Java Heap — 자매 영역

[process-thread-memory.md](./process-thread-memory.md) 1장의 "Heap" (= Process Heap, malloc 영역) 과 JVM 의 "Java Heap" 은 **같은 가상 주소 공간 안의 별개 영역**. 포함관계가 아니라 **자매 관계**.

```
프로세스 가상 주소 공간
├─ Process Heap  (brk/sbrk 영역)
│   ├─ C 의 malloc 이 다루는 곳
│   └─ JVM 도 일부 사용 (내부 자료구조, JNI 등)
│
└─ Java Heap    (mmap 으로 별도 reserve)
    ├─ Java 의 new 가 객체 할당하는 곳
    └─ GC 가 관리
```

#### 비교표

| | Process Heap | Java Heap |
|---|---|---|
| **다른 이름** | Native Heap, OS Heap, C Heap, malloc heap | JVM Heap, GC Heap |
| **누가 할당** | `malloc()` (C/C++) | `new` (Java) |
| **확장 방식** | `brk()`/`sbrk()` 로 점진 확장 | `mmap()` 으로 큰 덩어리 한 번에 |
| **누가 관리** | 개발자 `free()` | GC 자동 회수 |
| **크기 단위** | 작은 단위 (바이트 ~ KB) | 큰 덩어리 (수 GB) |
| **JVM 안 용도** | GC 부기, JNI, 작은 C++ 객체 | Java 객체, 배열, Class 미러 |

#### 교과서 그림 vs 실제 (JVM 프로세스)

```
[교과서적 Process Layout]              [실제 JVM 프로세스]
높은 주소  ┌─────────────┐              ┌─────────────────┐
          │   Stack     │              │ Thread Stacks   │  <- mmap
          ├─────────────┤              ├─────────────────┤
          │             │              │ Java Heap       │  <- JVM mmap
          │   <empty>   │              ├─────────────────┤
          │             │              │ Metaspace       │  <- JVM mmap
          ├─────────────┤              ├─────────────────┤
          │   Heap      │  ↑ brk       │ Code Cache      │  <- JVM mmap
          ├─────────────┤              ├─────────────────┤
          │   BSS       │              │ Shared libs     │  <- .so mmap
          │   Data      │              ├─────────────────┤
          │   Text      │              │   <empty>       │
낮은 주소  └─────────────┘              ├─────────────────┤
                                       │ Process Heap    │  <- brk (malloc)
                                       ├─────────────────┤
                                       │ BSS/Data/Text   │  <- JVM 바이너리
                                       └─────────────────┘
```

같은 프로세스 안에 **"Heap" 이 두 종류 공존**. 교과서 그림은 OS 개념 학습용 단순화이고, 실제 JVM 프로세스는 `pmap <PID>` 로 보면 mmap 영역이 훨씬 많다.

> JVM 만 그런 게 아니다. Python, Go, V8 (JS) 등 GC 가 있는 런타임은 다 비슷한 패턴 — 자기 객체 영역을 `mmap` 으로 따로 받아 자기가 관리.

#### 자주 헷갈리는 점

- "Heap" 이라는 단어가 문맥에 따라 다른 영역을 가리킨다. **C 책의 Heap = Process Heap, Java 책의 Heap = Java Heap.**
- JVM 도 C++ 프로그램이므로 **Process Heap 도 사용** (자기 내부 자료구조). 하지만 Java 객체는 절대 Process Heap 에 안 감.
- `malloc` 호출 -> Process Heap. `new` (Java) 호출 -> Java Heap. **다른 메커니즘.**

### 1.2 `mmap` 이란 무엇인가

위에서 계속 등장하는 `mmap` 의 정체.

#### 한 줄

`mmap` (memory map) = **Linux/UNIX syscall**. 프로세스의 가상 주소 공간에 **새 영역을 매핑**해달라고 OS 에 요청.

#### 시그니처

```c
void* mmap(void*  addr,    // 원하는 주소 (보통 NULL -> OS 가 알아서)
           size_t length,  // 크기
           int    prot,    // 권한 (PROT_READ, PROT_WRITE, PROT_EXEC)
           int    flags,   // 옵션 (MAP_ANONYMOUS, MAP_PRIVATE, MAP_SHARED ...)
           int    fd,      // 파일 디스크립터 (anonymous 면 -1)
           off_t  offset); // 파일 안의 오프셋
```

리턴값: **새로 매핑된 가상 주소 영역의 시작 주소**.

#### 두 가지 주요 용도

**(1) 익명 매핑 (`MAP_ANONYMOUS`)** — 그냥 메모리 덩어리, 파일과 무관

```c
void* p = mmap(NULL, 1024*1024*1024,        // 1 GB
               PROT_READ | PROT_WRITE,
               MAP_ANONYMOUS | MAP_PRIVATE,
               -1, 0);
// p 부터 1 GB 까지 가상 주소로 사용 가능
```

-> JVM 이 Java Heap, Metaspace, Code Cache 잡을 때 이걸 사용.

**(2) 파일 매핑** — 파일을 메모리처럼 접근

```c
void* p = mmap(NULL, file_size, PROT_READ, MAP_PRIVATE, fd, 0);
// 이제 p[0], p[1] 로 파일 내용 직접 읽기 (read() 호출 없이)
```

-> `.so` 라이브러리 로드, Java 의 `MappedByteBuffer`, DB 의 페이지 캐시 등.

#### `brk/sbrk` 와의 차이

| | `brk`/`sbrk` | `mmap` |
|---|---|---|
| **영역 수** | 1개의 연속된 Process Heap 만 | 매번 새 영역 |
| **위치** | Heap segment (BSS 위, 고정) | 가상 주소 공간 아무 곳 |
| **확장 방식** | 포인터 한 칸 위로 (작은 단위) | 큰 덩어리 한 번에 |
| **회수** | 작은 단위 회수 어려움 (단편화) | `munmap` 으로 깔끔히 반환 |
| **용도** | 작은 malloc (전통적) | 큰 할당, 별도 영역 |

> 사실 현대 `malloc` 은 둘 다 사용한다:
> - 작은 할당 (< ~128KB): `brk/sbrk` 로 Process Heap 안에서 처리
> - 큰 할당 (>= ~128KB): `mmap` 으로 별도 영역 (glibc 기본 동작)

#### lazy 특성 — 가장 중요한 포인트

`mmap` 은 **가상 주소만 reserve.** 물리 페이지는 **접근하는 순간** demand paging 으로 할당됨.

```c
void* p = mmap(NULL, 100L*1024*1024*1024, ...);  // 100 GB
// 이 시점: 가상 주소 100 GB 잡힘. 물리 RAM 사용 ~0

((char*)p)[0] = 1;
// 첫 페이지 접근 -> page fault -> 4KB 물리 페이지 할당
// 이 시점: 물리 RAM 사용 4KB
```

이 lazy 한 성질 때문에 `-Xmx 100g` 같은 큰 값도 작은 RAM 머신에서 시작 가능 (자세한 건 2.4 참조).

#### `pmap` 으로 확인

```bash
$ pmap <JVM PID>
00007f8c00000000  8388608K rw---   [ anon ]   # Java Heap (-Xmx 8g)
00007f8a00000000   524288K rw---   [ anon ]   # Code Cache
00007f8be0000000  1048576K rw---   [ anon ]   # Metaspace
...
00007f8d12345000     8192K rw---   [ stack ]  # thread stack
...
00007fa0bbb12000     2048K r-x--   libjvm.so  # JVM 바이너리 매핑
```

`[ anon ]` = 익명 매핑, 파일명이 보이는 것 = 파일 매핑. JVM 의 큰 영역들은 다 익명 매핑.

#### 한 줄 요약

> `mmap` = 가상 주소 공간에 새 영역을 통째로 받아오는 syscall. 익명 매핑이면 메모리 덩어리, 파일 매핑이면 파일을 메모리처럼. **JVM 의 모든 큰 영역 (Java Heap, Metaspace, Code Cache, Thread Stack) 은 `mmap` 으로 얻는다.**

### 1.3 Process Heap 의 본래 목적

JVM 만 보면 Process Heap 은 "보조 영역" 같지만, **OS 입장에선 이게 본래 메인**이고 Java Heap 같은 mmap 영역이 특수 용도.

#### 본래 목적 (C/C++ 세상)

`malloc`, `free`, `new`, `delete` 가 가는 **기본 동적 메모리 영역**. 모든 C/C++ 프로그램이 시작할 때 자동으로 받는 한 덩어리.

```c
char* buf = malloc(64);        // Process Heap
struct Node* n = new Node();   // Process Heap (C++)
char* s = strdup("hello");     // 내부 malloc -> Process Heap
FILE* f = fopen(...);          // FILE 구조체가 Process Heap 에
```

- 작은 단위 할당에 효율적 (free list, bins, slabs)
- `free` 한 메모리는 재사용 (OS 에 안 돌려주고 free list 보관)
- 모든 표준 라이브러리 (libc, libstdc++, OpenSSL, ...) 가 여기 씀

#### JVM 안에서의 역할

JVM 자체가 C++ 프로그램이므로 **자기 자신을 위한 메모리**가 Process Heap.

| 용도 | 무엇이 들어가나 |
|------|---------------|
| **JVM 내부 C++ 자료구조** | 스레드 매니저, 클래스 로더 자료, JIT 작업 큐 |
| **GC bookkeeping (일부)** | mark bitmap, remembered set, card table |
| **JIT 컴파일러 작업 메모리** | 바이트코드 분석 중간 데이터, IR 노드 |
| **JNI 할당** | 네이티브 라이브러리가 `malloc` 호출하면 여기 |
| **스레드 메타데이터** | PThread 구조체 (스택과는 별개) |
| **mmap 영역 관리 자료** | "내가 어느 mmap 영역 잡았다" 추적 자료 |

즉 **Java 객체 빼고 거의 모든 것**. JVM 이 자기 일을 하기 위한 작업 공간.

```
JVM (C++ 프로그램)
   ├─ 자기 자신을 위한 작은 자료구조    -> Process Heap (malloc)
   └─ Java 사용자 코드가 만든 객체      -> Java Heap (mmap + GC)
```

#### 왜 mmap 만 안 쓰고 brk Heap 도 필요한가

> **작은 할당에 mmap 은 비싸다.**

| | brk Heap (malloc) | mmap |
|---|---|---|
| 최소 단위 | 바이트 | 4 KB (1 페이지) |
| Syscall 비용 | 거의 없음 (라이브러리 내부 처리) | 매번 syscall |
| 8 바이트 할당 시 | 효율적 | 4 KB 잡음 (낭비) |
| 1 GB 할당 시 | brk 늘리면 단편화 | 깔끔 |
| 회수 | free list 에 반환 (재사용) | `munmap` 으로 OS 에 반납 |

**분업 구조**:
- 작고 빈번한 할당 -> brk Heap (malloc 의 free list)
- 크고 드문 할당 -> mmap

`malloc` 이 알아서 결정 (glibc 기준 ~128 KB 가 분기점).

```c
malloc(100);     // brk Heap 에서
malloc(1L << 30); // 내부적으로 mmap 호출 -> 별도 영역
```

#### 비유

```
한 동네 (가상 주소 공간) 안에:

Process Heap     = 잡화점
                   - 자잘한 것 (스테이플러, 펜) 거래
                   - 빠르고 효율적
                   - 늘 영업

Java Heap (mmap) = 대형 창고 분양
                   - 한 번에 100평 통째로 임대
                   - 안에서 어떻게 쓰는지는 임차인 (JVM) 마음대로
                   - 임대 끝나면 반납 (munmap)
```

#### JVM 만 두고 보면 Process Heap 이 안 보이는 이유

Java 개발자가 직접 `malloc` 을 안 부르니까 Process Heap 이 안 보일 뿐, 실제로는:

```
JVM 시작 -> Process Heap 자동으로 받음 (OS 기본 제공)
         -> JVM 내부에서 malloc 으로 활용
         -> 운영자 입장에선 RES 안에 포함되어 있음
```

`pmap` 으로 보면 `[ heap ]` 영역이 항상 보임 — 그게 Process Heap. 보통 수십 MB.

#### 한 줄

> Process Heap = C/C++ 동적 메모리의 기본 영역. JVM 안에서는 JVM 자체 (C++) 의 내부 자료구조 보관용. Java 객체는 안 들어감.
> **작고 빈번한 할당에 효율적**이라는 게 mmap 과 별도로 존재하는 이유.

### 1.4 GC 는 어디에서 작용하는가 — Process Heap 에도 GC 가 있나?

#### Java GC 의 작용 범위

```
Java GC 가 관리:
  ├─ Java Heap (Young + Old Gen)       <- 메인 대상
  ├─ Metaspace                         <- ClassLoader 죽을 때 그 안의 Klass 정리
  ├─ Code Cache                        <- JIT 코드 sweep (GC cycle 과 조율)
  └─ 일부 JVM 내부 hashtable           <- String table, Symbol table 등

Java GC 가 관리 안 함:
  ├─ Process Heap (malloc 영역)         <- 개발자/JNI 책임
  ├─ Thread Stacks                      <- 자동 LIFO
  ├─ Text/Data/BSS                      <- 정적
  └─ Direct ByteBuffer 의 native 버퍼   <- 간접적 (Cleaner)
```

Java GC 는 단순히 "Java Heap 만 청소" 가 아니라 **여러 영역을 함께 관리**.

#### Direct ByteBuffer — 흥미로운 경계

```java
ByteBuffer buf = ByteBuffer.allocateDirect(100 * 1024 * 1024);  // 100 MB
```

- `buf` 객체 자체 -> **Java Heap**
- 가리키는 100 MB 버퍼 -> **Native memory** (Process Heap 또는 mmap)
- `buf` 가 GC 되면? -> `Cleaner` (PhantomReference 기반) 가 native 버퍼를 `free`
- 즉 **GC 가 간접적으로 native memory 청소를 트리거**

이게 JVM 의 GC 가 "Java Heap 외 영역에도 영향을 미친다" 는 좁은 다리.

#### Process Heap (OS Heap) 에는 GC 가 있나?

**기본적으로 없다.** C/C++ 의 설계 철학: 프로그래머가 직접 관리 (`malloc`/`free`).

```c
char* p = malloc(1024);
// free 안 함
// -> 메모리 누수. 프로세스 종료 시까지 그대로.
// -> 프로세스 종료 시 OS 가 일괄 회수
```

#### 언어별 메모리 관리 비교

| 언어 | 메모리 관리 방식 | OS heap 사용? |
|------|---------------|--------------|
| **C** | 수동 (malloc/free) | 직접 사용, GC 없음 |
| **C++** | 수동 + smart pointer (RAII) | 직접 사용, GC 없음 |
| **Python** | 참조 카운트 + cycle detector | 자체 영역, OS heap 위 구현 |
| **Java** | Tracing GC | 별도 mmap 영역 (Java Heap) |
| **Go** | Concurrent tracing GC | 별도 mmap 영역 |
| **Rust** | 소유권/대여 (컴파일 타임) | 직접 사용, GC 없음, 누수도 거의 없음 |

#### C/C++ 의 우회로

1. **smart pointer** (C++): `unique_ptr`, `shared_ptr`, `weak_ptr`
   - RAII + 참조 카운트
   - 스코프 벗어나면 자동 해제
   ```cpp
   {
       auto p = std::make_unique<Node>();  // malloc
   }  // 스코프 끝 -> 자동 free
   ```

2. **Boehm GC** — C/C++ 에 실제 GC 를 붙이는 라이브러리
   ```c
   #include <gc.h>
   void* p = GC_malloc(1024);
   // free 안 해도 됨, GC 가 자동 회수
   ```
   - malloc 한 메모리 추적
   - 주기적으로 스택/전역/힙 스캔
   - 포인터로 추정되는 값 추적
   - 도달 불가 메모리 회수
   - **conservative GC** — 어떤 값이 진짜 포인터인지 정수인지 확신 못 해 보수적으로 판단 (false positive 가능)
   - 사용 예: GCC 컴파일러 일부, Mono 초기 버전 등

3. **valgrind**, **AddressSanitizer**: 누수 검출 도구 (GC 는 아님, 디버깅용)

#### 왜 OS Heap 자체에는 GC 가 없나 — 설계 철학

```
GC 가 있으려면:
  - 모든 포인터를 추적할 수 있어야 함
  - 메모리 레이아웃 정보 (객체 크기, 참조 필드 위치) 가 필요
  - 안전한 stop-the-world 가능해야 함

C/C++ 에선:
  - 포인터와 정수의 구분이 어려움 (캐스팅 자유로움)
  - 객체 메타데이터 없음 (struct 크기 외엔 런타임 정보 없음)
  - 임의의 메모리 접근 자유로움

-> GC 와 C/C++ 의 메모리 모델은 근본적으로 맞지 않음
-> 그래서 GC 가 필요한 언어들 (Java, Go, ...) 은 자기만의 heap 을 만들고
   메타데이터를 객체마다 박아넣어 GC 가능하게 설계
```

이래서 **GC 언어들은 OS heap 을 직접 안 쓰고 자기 mmap 영역에 자기 heap 을 만든다.**

#### 한 줄

> **Java GC 의 작용 범위 = Java Heap + Metaspace + Code Cache + 일부 내부 자료구조.** Process Heap 은 손 안 댐.
> **OS Heap 에는 GC 없음**이 기본 — C/C++ 의 자유로운 메모리 모델과 GC 가 양립 불가. C++ 은 smart pointer 로, Rust 는 컴파일러로, Boehm GC 는 보수적 추적으로 우회.
> GC 가 필요한 언어들은 OS heap 대신 자기 mmap 영역에 자체 heap 을 만들어 그 안에서 GC.

### 1.5 OS Heap 은 꽉 차지 않나? — 누수와 관리, 그리고 사용자에게 안 보이는 이유

GC 가 없다면 OS Heap 은 어떻게 관리되는가? 그리고 일상적으로 컴퓨터 쓸 때 메모리 관리를 안 해도 되는 이유는?

#### "꽉 찬다" 의 두 가지 의미

**(1) 가상 주소 공간 차원**: 64-bit 면 사용자 공간 128 TB. 현실에서 거의 안 참 (무한 누수 아니면).

**(2) 물리 RAM + Swap 차원**: 이게 진짜 마주치는 천장.

```
malloc(big chunk)
   ↓
가상 주소 할당됨
   ↓
실제 접근 -> page fault -> 물리 페이지 필요
   ↓
RAM + Swap 다 참
   ↓
malloc 이 NULL 리턴, 또는 OS 의 OOM Killer 가 프로세스 사살
```

#### 누가 관리하나 (GC 없이)

| 방법 | 어떻게 |
|------|--------|
| **수동 `free()`** | 프로그래머가 malloc 마다 짝 맞춰 free 호출 |
| **RAII (C++)** | 스코프 벗어나면 소멸자가 자동 free |
| **smart pointer (C++)** | `unique_ptr`, `shared_ptr` 참조 카운트로 자동 |
| **메모리 풀** | 미리 할당해서 재사용, 외부에는 안 돌려줌 |
| **누수 검출 도구** | `valgrind`, AddressSanitizer (ASan), heaptrack |
| **외부 GC 라이브러리** | Boehm GC (drop-in 가능) |

#### 가장 헷갈리는 미묘함 — `free` 는 OS 에 메모리를 안 돌려준다

```c
char* p = malloc(1024);
free(p);  // <- 이 시점에 OS 에 반납되는 게 아님
```

`free` 가 하는 일:
- `malloc` 의 내부 **free list** 에 "이 메모리는 재사용 가능" 표시
- 다음 `malloc` 호출 때 재사용
- **OS 한테는 안 돌려줌** (대부분의 경우)

그래서:

```
[T=0] malloc(1GB)   -> RSS 1GB
[T=1] free(p)       -> RSS 여전히 1GB (free list 에만)
[T=2] malloc(500MB) -> 그 free list 에서 재사용, RSS 그대로 1GB
```

`top` 의 RSS 가 잘 안 줄어드는 이유. 프로세스가 "한 번 도달한 high-water mark" 를 계속 들고 있는 경향.

**예외**: 큰 chunk (mmap 으로 잡힌 것) free 시에는 `munmap` 으로 진짜 OS 반환. 그래서 mmap 영역 (Java Heap, 큰 malloc) 은 free 시 OS 반환되지만, brk 영역의 작은 것들은 RSS 에 그대로 남는다.

`malloc_trim(0)` 으로 명시적 trim 가능하지만, free list 가 fragmented 되어 있으면 효과 적음.

#### 일상적으로 컴퓨터 쓸 때 왜 관리가 안 보이나 — 두 가지 안전망

**(1) 프로세스 종료 시 OS 가 일괄 회수** ← 가장 강력한 안전망

```
프로그램 실행
  ↓
malloc, malloc, malloc, ... (free 하나도 안 함, 누수 천국)
  ↓
프로그램 종료
  ↓
OS: "이 프로세스 가상 주소 공간 통째로 회수"
   ├── 페이지 테이블 free
   ├── 모든 mmap 영역 회수
   ├── Process Heap 통째로 회수
   ├── Stack 회수
   └── 모든 물리 페이지 다시 free list 로
  ↓
완전 깨끗 ✓
```

즉 **"한 번의 실행 동안만 누수 없으면 사실상 문제 없다."** 프로그램 끝나는 순간 다 청소됨.

그래서 **짧은 수명 프로그램은 사실상 관리 불필요**:

```
ls /tmp           - 100ms 실행 -> 종료 -> OS 가 다 청소
python script.py  - 5초 실행 -> 종료 -> OS 가 다 청소
grep foo file.txt - 50ms 실행 -> 종료 -> OS 가 다 청소
```

실제로 `ls`, `cat` 같은 명령어 소스를 보면 `free` 호출이 별로 없음. 짧은 수명이라 굳이 관리할 이유가 없으니까.

**(2) 개발자가 코드 안에서 관리 (사용자 모르게)**

긴 수명 프로그램들 (Chrome, 게임, 운영체제 서비스) 은 다 개발자들이 코드에서 꼼꼼히 관리한 것.

```cpp
// Chrome 개발자가 쓴 코드 (대략적 상상)
class Tab {
    std::unique_ptr<Renderer> renderer;  // RAII
    std::vector<Resource*> resources;

    ~Tab() {                              // 탭이 닫힐 때
        for (auto* r : resources) delete r;
    }
};
```

사용자가 탭을 닫을 때 -> 소멸자 자동 호출 -> 자원 해제. **눈에 안 보일 뿐 누군가는 코드를 짠 것.**

#### 사용자도 사실은 메모리 관리하고 있다

```
"Chrome 이 느려졌네, 재시작하자"        <- OOM killer 역할
"노트북이 버벅거려, 재부팅하자"          <- 메모리 압박 해소
"이 앱 안 쓰는데 닫자"                  <- 메모리 회수 명령
```

기술적으로 이게 다 메모리 관리. 자각 못 할 뿐 매일 하고 있음. 특히 **앱 종료 = 그 프로세스의 모든 메모리 회수**.

#### 그래서 진짜 문제가 되는 상황 = 장수 프로세스

- 서버 데몬 (Nginx, Postgres, MySQL)
- 백엔드 애플리케이션 (24/7)
- 임베디드 시스템 (재부팅 거의 없음)
- 게임 서버, 장수 IDE/브라우저

여기서 누수 있으면:
- 처음엔 멀쩡
- 한 주 지나면 RSS 2배
- 한 달 지나면 OOM
- 운영자가 주기적 재시작 (강제 회수)

#### 그래서 GC 가 진짜 필요한 이유

```
짧고 단순한 프로그램 (CLI 도구):
  - OS 종료 시 회수면 충분
  - GC 불필요

길고 단순한 프로그램 (네트워크 데몬):
  - 수동 관리로도 가능
  - smart pointer, RAII 로 해결

길고 복잡한 프로그램 (Java 서버, 게임 서버):
  - 객체 수만 개, 참조 그래프 복잡
  - 수동 관리는 사실상 불가능
  - GC 가 진짜 가치 있는 영역
```

Java, Go, C# 같은 GC 언어가 **장수 + 복잡** 영역에서 주로 쓰이는 이유.

#### JVM 의 Native Memory 누수 시나리오 (운영 현실)

| 누수 원인 | 어디에 쌓이나 |
|----------|-------------|
| **JNI 라이브러리 버그** | malloc 만 하고 free 안 함 -> Process Heap |
| **Metaspace 무한 증가** | 동적 클래스 로딩 (Spring proxy, Groovy) -> Metaspace |
| **DirectByteBuffer 누수** | Cleaner 가 안 도는 경우 -> native memory |
| **Thread 누수** | 스레드 안 죽으면 스택 영역도 계속 살아있음 |
| **JIT Code Cache full** | 너무 많은 메서드 컴파일 |

증상: **`-Xmx` 한참 안 넘는데 RSS 가 계속 증가** -> Java Heap 외 native memory 누수 의심.

#### 진단 도구

```bash
# 1. Native Memory Tracking (NMT) — JVM native 영역별 사용량
java -XX:NativeMemoryTracking=detail ...
jcmd <PID> VM.native_memory summary

# 2. pmap — 프로세스 메모리 매핑 전체
pmap -x <PID>

# 3. RSS 추적
ps -o pid,rss,vsz,cmd -p <PID>

# 4. JNI 의심되면 valgrind / ASan
LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libasan.so java ...
```

NMT 출력 예:
```
Total: reserved=10GB, committed=3.2GB
  Java Heap:  reserved=8GB,   committed=2GB     <- -Xmx 안
  Class:      reserved=1GB,   committed=200MB   <- Metaspace
  Thread:     reserved=200MB, committed=50MB    <- Stack
  Code:       reserved=240MB, committed=80MB    <- Code Cache
  GC:         reserved=300MB, committed=150MB   <- GC 내부
  Internal:   reserved=50MB,  committed=50MB
```

`Internal` 이나 `Other` 가 비정상적으로 크면 native 누수 의심.

#### JVM 으로 묶으면

```
JVM 프로세스:
  ├─ Process Heap (malloc 영역)
  │   └─ JVM 자체가 C++ 로 작성된 코드라 개발자들이 꼼꼼히 관리
  │      (HotSpot 개발자들이 일 잘함)
  │
  └─ Java Heap (mmap 영역)
      └─ GC 가 자동 관리
      └─ Java 개발자는 메모리 신경 안 써도 됨
```

Java 개발자가 메모리에서 자유로운 진짜 이유: **HotSpot 개발자들이 Process Heap 을 꼼꼼히 관리해주고 + Java Heap 에는 GC 가 돌아서 두 종류 모두 자동화되어 있는 것.**

C/C++ 개발자는 이 자동화가 없어서 직접 해야 함.

#### 한 줄 정리

> **사용자가 OS Heap 을 관리 안 해도 되는 이유 = (1) 프로세스 종료 시 OS 자동 회수 + (2) 개발자가 코드에서 관리.**
> 짧은 프로그램은 (1) 로 충분, 긴 프로그램은 (2) 가 필수.
> 사용자의 "앱 닫기, 재시작" 이 사실 (1) 안전망을 트리거하는 메모리 관리 행위.
> "`free` 가 OS 반환이 아니다" 라는 사실이 가장 자주 사람을 헷갈리게 하는 포인트.

### 1.6 JVM Heap 한 줄 정의 — 멘탈 모델

여기까지 본 내용을 한 문장으로 응축하면:

> **"자바 어플리케이션만을 위한 힙을 새로 만들었다."**

거의 정확한 표현. 살짝 다듬으면 완벽한 정의가 된다.

#### 정확한 한 줄

> **JVM 이 시작할 때 OS 한테 `mmap` 으로 별도 큰 영역을 받아, Java 객체 전용 공간으로 자기가 GC 관리하는 곳.**

#### 네 가지 요소 — 어느 것 하나 빠뜨리면 안 됨

| 요소 | 의미 |
|------|------|
| **JVM 이 시작할 때 받음** | 한 번 영구히 만든 게 아니라, JVM 프로세스마다 새로 mmap |
| **별도 영역** | OS 의 Process Heap (brk) 과 다른 곳 |
| **Java 객체 전용** | C 의 malloc 결과는 절대 안 옴, `new` 만 옴 |
| **GC 가 관리** | malloc/free 가 아니라 추적식 자동 회수 |

#### 외우기 버전

> **"JVM 이 OS 에서 통째로 임대받아 GC 로 굴리는, Java 객체 전용 별도 메모리 영역."**

#### "자바 어플리케이션" vs "자바 객체" — 미묘한 차이

```
"자바 어플리케이션을 위한"  → 약간 광범위. JVM 전체가 다 자바 앱을 위한 거니까
"자바 객체를 위한"          → 더 정확. Java Heap 의 진짜 입주자는 객체뿐
```

JVM 안에는 사실 **자바 앱을 위한 영역이 여러 개**:
- **Java Heap** → 객체
- **Metaspace** → 클래스 메타데이터 (Klass)
- **Code Cache** → JIT 코드
- **Thread Stack** → 메서드 호출 흐름

이 중 **Java Heap = 객체 전용**.

#### 같은 패턴의 다른 런타임들

Java 만 그런 게 아님. **GC 가 필요한 모든 런타임이 같은 패턴**을 사용한다.

| 런타임 | 자체 Heap | 관리 방식 |
|--------|----------|----------|
| **JVM** | Java Heap (mmap) | Tracing GC |
| **Go runtime** | Go Heap (mmap) | concurrent GC |
| **CPython** | Python Object Heap | 참조 카운트 + cycle GC |
| **V8 (Node.js)** | V8 Heap | generational GC |
| **.NET CLR** | Managed Heap | GC |

다 똑같이 OS Heap 안 쓰고 자기만의 큰 영역을 따로 받아서 자기 룰로 관리. **Java Heap 은 이 패턴의 하나일 뿐.**

#### 최종 멘탈 모델

```
OS 가 주는 기본 부지 (가상 주소 공간)
   │
   ├─ OS 가 자동으로 준 잡화점        → Process Heap (malloc 용)
   │                                     - JVM 자체의 작은 자료구조
   │                                     - 모든 C/C++ 프로그램 기본
   │
   └─ JVM 이 따로 분양받은 단지        → Java Heap
       └─ "이 안에서는 내가 GC 로 관리할게요"
       └─ Java 의 new 가 들어오는 유일한 곳
       └─ JVM 종료 시 단지 자체 반납
```

#### 한 줄 묶음

> **"JVM 이 자바 객체 살게끔 OS 한테 따로 분양받은 단지."** — 이 비유 하나면 Java Heap 의 본질을 다 담는다.

---

## 2. JVM 프로세스 메모리 전체 그림

```
JVM Process Virtual Address Space
┌──────────────────────────────────────────────────────┐
│ JVM Binary (Text/Data/BSS)                           │
├──────────────────────────────────────────────────────┤
│ ┌──────────────────────────────────────────────────┐ │
│ │ Java Heap  (-Xmx)                                │ │
│ │  ┌────────────────────────────────────────────┐  │ │
│ │  │ Young Gen  (Eden, Survivor)                │  │ │
│ │  ├────────────────────────────────────────────┤  │ │
│ │  │ Old Gen                                    │  │ │
│ │  └────────────────────────────────────────────┘  │ │
│ └──────────────────────────────────────────────────┘ │
│                                                      │
│ ┌──────────────────────────────────────────────────┐ │
│ │ Native Memory  (non-Java-Heap dynamic regions)   │ │
│ │  ┌────────────────────────────────────────────┐  │ │
│ │  │ Metaspace     - Klass, methods, constants  │  │ │
│ │  ├────────────────────────────────────────────┤  │ │
│ │  │ Code Cache    - JIT-compiled native code   │  │ │
│ │  ├────────────────────────────────────────────┤  │ │
│ │  │ Direct ByteBuffer (NIO)                    │  │ │
│ │  ├────────────────────────────────────────────┤  │ │
│ │  │ JNI allocations, GC internal structs       │  │ │
│ │  └────────────────────────────────────────────┘  │ │
│ └──────────────────────────────────────────────────┘ │
│                                                      │
│ ┌──────────────────────────────────────────────────┐ │
│ │ Thread Stacks  (one per thread, -Xss)            │ │
│ └──────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────┘

  JVM Binary    : JVM 자체 실행 코드
  Java Heap     : GC 가 관리. Java 객체 (Class 미러 포함)
  Native Memory : JVM 내부용. Java Heap 이 아닌 동적 영역들
  Thread Stacks : 스레드마다 1개
```

`-Xmx8g` 해놨다고 RES 가 8GB 만 되는 게 아니다. **Metaspace + Code Cache + Direct Buffer + 스레드 스택** 까지 더해야 진짜 RSS. "왜 `-Xmx` 보다 메모리를 더 먹지?" 의 원인.

### 2.1 영역 간 포함관계 — 헷갈리기 쉬운 포인트

위 다이어그램에서 **JVM 바이너리 / Java Heap / Native Memory** 셋의 관계가 모호하게 보일 수 있다. 정리:

```
JVM 프로세스 가상 주소 공간  ← 부모 (이게 모든 걸 담는 광장)
├── JVM 바이너리 (Text/Data/BSS)
├── Java Heap
└── Native Memory (그 외 동적 영역들)
```

- 셋은 **서로 포함하지 않는 별개 영역**. A ⊂ B 관계 없음.
- 셋 다 **프로세스 가상 주소 공간 안에** 있음 (이게 부모).
- 비유: 한 부동산 안의 사무실 건물 (JVM 바이너리) + GC 가 관리하는 창고 (Java Heap) + 그 외 잡다한 공간 (Native Memory).

#### "Native Memory" 는 우산 용어다

`Native Memory` 는 **단일 영역 이름이 아니라 여러 영역을 묶어 부르는 통칭**. 그래서 정의가 미묘하게 흔들린다.

| 정의 | 범위 | 누가 쓰나 |
|------|------|----------|
| **좁은 의미** (실무 표준) | Java Heap 이 아닌, JVM 이 동적으로 잡는 모든 영역 (Metaspace, Code Cache, Direct Buffer, 스레드 스택, JNI, GC 내부 등) | NMT, jcmd, 모니터링 툴 |
| **넓은 의미** | Java Heap 을 제외한 프로세스의 모든 메모리. **JVM 바이너리도 포함** | OS 의 RSS 관점 |

이 문서는 **좁은 의미**를 채택한다. (= JVM 바이너리는 Native Memory 와 별개로 표시)

#### 좀 더 정확한 OS 관점 그림

```
JVM 프로세스 가상 주소 공간
├─ [정적] OS 가 프로세스 시작 시 로드
│   ├─ Text/Data/BSS (JVM 실행 코드 = libjvm.so 등)
│   └─ 그 외 .so 라이브러리들
│         ↑ 이걸 "JVM 바이너리" 라고 부른 것
│
├─ [동적: mmap 으로 큰 덩어리 예약]
│   ├─ Java Heap     ─── GC 가 관리
│   ├─ Metaspace    ─── ClassLoader 단위로 관리
│   ├─ Code Cache   ─── JIT 가 관리
│   ├─ Direct ByteBuffer
│   └─ Thread Stacks (스레드마다 1개)
│
└─ [동적: malloc 으로 작은 단위 할당]
    └─ OS Heap ─── JNI, GC 내부 자료구조 등
        ↑ 진짜 C 의 malloc 이 다루는 영역
```

> **정정**: 위 [2장 다이어그램에서 "Native Memory (= OS heap, malloc 영역)" 라고 쓴 부분은 단순화]. 실제로 **Metaspace 와 Code Cache 는 malloc 이 아니라 mmap 으로 별도 예약**된 영역이고, JVM 이 그 안에서 자체 allocator 로 관리한다. "OS heap (= malloc 영역)" 과 "JVM 의 비-Java-Heap mmap 영역들" 은 OS 입장에서 서로 다른 메커니즘이다.

#### 포함관계 표

| 영역 A | 영역 B | 관계 |
|--------|--------|------|
| 프로세스 가상 주소 공간 | JVM 바이너리 | A ⊃ B |
| 프로세스 가상 주소 공간 | Java Heap | A ⊃ B |
| 프로세스 가상 주소 공간 | Native Memory | A ⊃ B |
| JVM 바이너리 | Java Heap | 별개 (교집합 없음) |
| Java Heap | Native Memory (좁은 의미) | 별개 |
| JVM 바이너리 | Native Memory (좁은 의미) | 별개 |
| JVM 바이너리 | Native Memory (넓은 의미) | B ⊃ A |

#### 한 줄로

> **프로세스 가상 주소 공간 = 광장. JVM 바이너리 + Java Heap + Native Memory = 그 광장을 나눠 쓰는 별개 구역들.** "Native Memory" 만 우산 용어라 정의에 따라 JVM 바이너리를 품기도 하지만, 실무에선 보통 "Java Heap 도 JVM 바이너리도 아닌 동적 영역들"을 가리킨다.

### 2.2 가상 주소 공간의 소유권 — 프로세스 당 1개

가상 주소 공간은 **CPU 코어 당이 아니라 프로세스 당 1개**. 절대 규칙.

```
프로세스   --1:1-->   가상 주소 공간   --1:1-->   페이지 테이블
   |
   | 1:N
   v
스레드들 (모두 같은 페이지 테이블 공유)
   |
   | N:M (스케줄러가 결정)
   v
CPU 코어들 (페이지 테이블을 임시 로드해서 사용)
```

CPU 코어는 가상 주소 공간의 "주인"이 아니라 **현재 어느 프로세스의 페이지 테이블을 보는지** 매 순간 바꿔가며 일하는 사서.

#### CPU 가 페이지 테이블을 다루는 방식

```
CPU 의 CR3 레지스터 (x86 기준)
        |  가리킴
        v
현재 프로세스의 페이지 테이블 (커널 메모리 안)
        |
        v
이걸로 가상 -> 물리 변환 (MMU 가 수행)
```

OS 가 context switch 할 때 CR3 값을 바꿔준다. **CPU 는 페이지 테이블을 소유하지 않고, 단지 사용할 뿐.**

#### 멀티코어 시나리오

```
JVM 프로세스 1개 (스레드 100개), 8 코어 머신

  Core 1 --[T1 of JVM]--> CR3 = JVM page table --> JVM 주소 공간
  Core 2 --[T2 of JVM]--> CR3 = JVM page table --> JVM 주소 공간
  Core 3 --[T3 of JVM]--> CR3 = JVM page table --> JVM 주소 공간
  ...

-> 모든 코어가 같은 페이지 테이블 로드
-> 같은 가상 주소 = 같은 물리 페이지
-> 스레드들끼리 객체를 포인터로 직접 공유 가능
```

이래서 **JVM 안 100개의 스레드가 같은 Java Heap 의 객체를 공유**할 수 있다. 모두 같은 페이지 테이블을 보기 때문.

#### Context switch — 가장 비싼 순간

```
Core 1 에서:

[T=0] 프로세스 A 의 스레드 실행 중
       CR3 = A's page table
       TLB 캐시 채워짐

[T=1] OS scheduler: "이제 B 차례"
       ├── A 의 레지스터 저장
       ├── CR3 = B's page table     <- 페이지 테이블 교체
       └── TLB flush                <- A 의 캐시 다 버림 (느림)

[T=2] B 의 스레드 실행 시작
       TLB miss 폭증 (다시 채워야 함)
```

같은 프로세스 안의 **스레드 전환**은 CR3 가 그대로라 TLB 유효 -> 빠름. 그래서 스레드 컨텍스트 스위칭이 프로세스 컨텍스트 스위칭보다 훨씬 가볍다.

> 자세한 페이지 테이블/TLB 동작은 [process-thread-memory.md](./process-thread-memory.md) 4장 참조.

### 2.3 가상 주소 공간의 생성과 소멸

**프로세스 ↔ 가상 주소 공간 = 1:1 lifecycle.** 프로세스가 태어나는 순간 같이 태어나고, 죽으면 같이 사라진다.

#### 생성 흐름 — `java Hello` 추적

```
$ java Hello
        |
        v
[1] shell 이 fork() syscall 호출
        |
        v
[2] OS 가 새 프로세스 생성
        ├── task_struct (PCB) 새로 만듦
        ├── mm_struct 새로 만듦
        ├── 페이지 테이블 새로 만듦         <- 가상 주소 공간의 실체
        └── 부모 페이지 테이블 복사 (실제 페이지는 COW 공유)
        |
        v
[3] child 가 exec("java") syscall 호출
        |
        v
[4] OS 가 address space 통째로 교체
        ├── 기존 매핑 다 버림
        ├── java 바이너리 Text/Data 매핑
        ├── Stack 영역 예약
        └── Heap 영역 예약
        |
        v
[5] JVM 코드가 main 진입점부터 실행
        |
        v
[6] JVM 이 추가 mmap() 으로 영역 예약
        ├── Java Heap (-Xmx 만큼)
        ├── Metaspace
        └── Code Cache
```

**[2] 단계에서 이미 가상 주소 공간이 만들어진다.** [6] 의 JVM mmap 은 "이미 만들어진 주소 공간 안에 영역을 추가 reserve" 하는 것일 뿐.

#### 무엇이 진짜로 만들어지나

| 만드는 것 | 어디 저장 | 역할 |
|----------|---------|------|
| **task_struct (PCB)** | 커널 메모리 | 프로세스 메타데이터 |
| **mm_struct** | 커널 메모리 | 메모리 매핑 정보 묶음 |
| **vm_area_struct 리스트** | 커널 메모리 | 어느 가상 주소 범위가 어떤 용도인지 |
| **페이지 테이블** | 커널 메모리 | 가상 -> 물리 매핑 실체 |

이 자료구조들이 묶여서 "이 프로세스의 가상 주소 공간"을 구성한다. 처음엔 대부분 비어있거나 demand paging 으로 lazy 하게 채워짐.

#### 프로세스 종료 시

```
process exit (or kill -9)
    |
    v
OS:
   ├── 매핑된 물리 페이지들 해제 (free list 로 반환)
   ├── 페이지 테이블 free
   ├── vm_area_struct 리스트 free
   ├── mm_struct free
   └── task_struct 제거
    |
    v
가상 주소 공간 완전 소멸
```

JVM 종료되면 `-Xmx 8GB` 잡고 있던 Java Heap, Metaspace, Code Cache 다 같이 사라짐.

#### 스레드 생성과의 차이 — Linux clone() 의 통합 관점

Linux 커널은 프로세스와 스레드를 **같은 syscall (`clone()`)** 로 만들고, 어떤 자원을 공유할지만 flag 로 구분한다.

```
fork()              = clone() with NO sharing flag
                      -> 새 task_struct + 새 mm_struct + 새 페이지 테이블
                      -> 새 가상 주소 공간 ✓

pthread_create()    = clone() with CLONE_VM flag
                      -> 새 task_struct, 하지만 mm_struct 는 공유
                      -> 같은 페이지 테이블 사용
                      -> 가상 주소 공간 공유 (안 만듦) ✓
```

| 무엇 | task_struct | mm_struct (가상 주소 공간) |
|------|-------------|--------------------------|
| 프로세스 생성 (`fork`) | 새로 만듦 | **새로 만듦** |
| 스레드 생성 (`pthread_create`) | 새로 만듦 | **공유** (`CLONE_VM`) |

**핵심**: 새 task_struct 가 만들어진다고 무조건 새 주소 공간이 생기는 게 아님. **`mm_struct` 가 새로 만들어졌는지**가 결정.

### 2.4 가상 주소 공간의 한계 — 무한일까?

**아니, 한계가 있다.** 세 가지 천장에 동시에 부딪힌다.

```
세 가지 한계:
  (1) CPU 아키텍처     - 절대 천장 (하드웨어)
  (2) OS 분할          - 그 안에서 더 좁힘
  (3) 백킹 저장소       - 실제로 채울 수 있는 양
```

다만 핵심: "**예약**" 까지는 lazy 라서 거의 공짜. 이게 큰 가상 주소를 작은 RAM 으로도 잡을 수 있는 이유.

#### (1) CPU 아키텍처 — 절대 천장

가상 주소는 결국 비트로 표현되는 정수. CPU 의 주소 비트 수가 천장.

| 아키텍처 | 유효 주소 비트 | 최대 가상 주소 공간 |
|---------|--------------|---------------------|
| 32-bit (x86) | 32 bits | 2^32 = **4 GB** |
| 64-bit (x86_64, 일반) | 48 bits | 2^48 = **256 TB** |
| 64-bit (5-level paging, 최신) | 57 bits | 2^57 = **128 PB** |
| ARM64 | 48 bits | 256 TB |

> 64비트 CPU 가 이론상 2^64 = 16 EB 같지만, 페이지 테이블 구조 한계로 48~57 비트만 유효. 상위 비트는 **non-canonical** 영역이라 못 씀.

#### (2) OS 분할 — 사용자/커널 나누기

```
Linux x86_64 (48-bit) 가상 주소 공간 분할

0x0000_0000_0000_0000  ┌──────────────────────┐
                       │ Userspace            │  ~128 TB
                       │ (process region)     │
0x0000_7FFF_FFFF_FFFF  ├──────────────────────┤
                       │ Non-canonical hole   │  unavailable
0xFFFF_8000_0000_0000  ├──────────────────────┤
                       │ Kernel space         │  ~128 TB
                       │ (shared by all)      │
0xFFFF_FFFF_FFFF_FFFF  └──────────────────────┘
```

256 TB 중 절반은 커널이 차지. **사용자 프로세스는 ~128 TB 까지만** 사용 가능.

#### (3) 백킹 저장소 (RAM + Swap) — 진짜 데이터의 천장

가상 주소를 아무리 크게 잡아도, 실제 데이터가 들어가는 페이지는 **RAM/swap 으로 받쳐줘야** 함.

```
RAM 16 GB + Swap 8 GB = 24 GB
        ^
"가상 주소 공간이 아니라 이게 진짜 데이터의 천장"
```

가상 주소는 128 TB 까지 잡을 수 있지만, 실제 채울 수 있는 양은 RAM + swap. 그 이상 채우려 하면 OOM Killer 발동.

#### "예약" 까지는 lazy — 거의 공짜

```
mmap(NULL, 1 TB, PROT_READ|PROT_WRITE, MAP_ANONYMOUS|MAP_PRIVATE, -1, 0)
        |
        v
[OS]
- vm_area_struct 에 "이 가상 주소 1TB 예약됨" 기록
- 페이지 테이블은 거의 그대로 (entry 비어있음)
- 물리 페이지 할당 0 개
        |
        v
"1 TB 예약, RAM 거의 안 씀" ✓
```

실제로 접근하는 순간 **demand paging** 으로 물리 페이지가 점진적으로 할당됨.

| 동작 | 가상 주소 사용 | 물리 RAM 사용 |
|------|--------------|--------------|
| mmap 으로 1 TB reserve | 1 TB | ~0 |
| 그 중 1 MB 만 실제 접근 | 1 TB | 1 MB |
| 1 TB 전체 touch | 1 TB | RAM 한계 + swap |
| RAM + swap 다 부족 | 실패 | OOM |

> 자세한 demand paging 동작은 [process-thread-memory.md](./process-thread-memory.md) 5장 참조.

#### JVM 의 `-Xmx100g` 가 16 GB 머신에서 시작되는 이유

```bash
java -Xmx100g Hello   # Java Heap 최대 100 GB 설정
```

```
[JVM 시작]
mmap(100 GB, ...) 호출
        |
        v
가상 주소 100 GB 예약, 페이지 테이블은 거의 안 만들어짐
RAM 사용량: 약 수십 MB (JVM 자체)
        |
        v
JVM 시작 성공 ✓
        |
        v
[실행 중]
객체 생성 -> Heap 점진 접근
        |
        v
Page Fault -> 물리 페이지 점진 할당
RAM 사용량: 점점 증가
        |
        v
RAM 16 GB 한계 도달
        |
        v
오래된 페이지가 Swap 으로 밀려나기 시작 (성능 급락)
        |
        v
Swap 8 GB 도 가득 차면
        |
        v
OutOfMemoryError 또는 OOM Killer
```

`-XX:+AlwaysPreTouch` 옵션은 시작 시 100 GB 전체에 미리 touch 해서 페이지 fault 강제 발생 -> 모든 페이지가 미리 할당됨. 16 GB 머신에선 이 옵션 켜면 시작 자체가 실패할 수 있음.

#### 정리표

| 측면 | 한계 | 비고 |
|------|------|------|
| **CPU 아키텍처** | 32-bit: 4 GB / 64-bit: 256 TB | 절대 천장 |
| **OS 분할** | 사용자 공간 ~128 TB (Linux x86_64) | 실질적 천장 |
| **백킹 (RAM + Swap)** | 머신마다 다름 (GB ~ TB) | 진짜 데이터 천장 |
| **예약 (mmap)** | OS 한계 안에서 자유 | RAM 거의 안 씀, lazy |
| **실사용 (touch)** | RAM + Swap 안에서만 | 넘으면 OOM |

#### 한 줄 묶음

> 가상 주소 공간은 **무한 X**. CPU 비트가 절대 천장, OS 가 더 좁히고, 실제 데이터는 RAM + swap 만큼만 채울 수 있다.
> 다만 "**예약만 하기**"는 lazy 라서 거의 공짜 — 이게 `-Xmx 100g` 같은 옵션이 작은 RAM 머신에서도 시작은 되는 이유.

#### 심화 FAQ — 자주 헷갈리는 두 가지

##### Q1: 가상 주소를 무한히 만들어두고 page fault 로 처리하면 안 되나?

> "어차피 가상 주소는 fake 잖아? 그러면 무한히 크게 잡아두고, RAM 에서 필요할 때 가져오면 되는 거 아닌가?"

**핵심**: 가상 주소가 fake 라고 **데이터가 fake 인 건 아니다.**

```
int x = 5;   // 가상 주소 0x7f1000 에 저장
   ↓
CPU 가 0x7f1000 -> MMU -> 페이지 테이블 조회
   ↓
물리 페이지 없음 -> Page Fault
   ↓
OS: "RAM 에서 빈 프레임 하나 찾아서 매핑"
   ↓
값 5 가 그 물리 RAM 프레임에 실제로 저장됨
```

값 5 는 **반드시 어딘가 실재하는 물리 RAM 또는 swap 디스크에 들어가야 한다.** 가상 주소만으로는 값을 못 저장.

**그래서 세 가지 진짜 천장이 있다:**

1. **CPU 비트 한계** (절대적): x86_64 MMU 는 48비트만 처리. "무한 가상 주소" 자체가 하드웨어적으로 불가능.
2. **Page Table 비용**: 매핑된 페이지마다 PTE 8바이트. 100GB 다 commit 하면 PT 만 ~200MB.
3. **RAM + Swap = 진짜 데이터 천장**: 데이터가 어딘가 저장돼야 함. 그 이상 쓰면 OOM Killer.

**Page Fault 가 만능이 아닌 이유**:

```
Page Fault 동작:
  ├─ "이 가상 주소에 매핑된 물리 페이지 없음"
  └─ OS 가 빈 물리 페이지를 찾아서 매핑

빈 물리 페이지가 없으면?
  ├─ 다른 페이지를 swap 으로 내보냄 (LRU)
  └─ swap 도 가득 차면 OOM
```

Page Fault 는 **있는 RAM 을 효율적으로 매핑할 뿐, 없는 RAM 을 만들어내지 않는다.**

**Demand Paging 의 진짜 한계 = Working Set**:

```
Working Set = 현재 실제로 활발히 쓰는 페이지 집합

WS < RAM         -> 잘 돌아감 (page fault 가끔)
WS > RAM         -> Thrashing (계속 swap in/out, 성능 급락)
WS > RAM + Swap  -> OOM
```

가상 주소를 100TB 잡아도, 실제 쓰는 양이 RAM 을 넘으면 thrashing.

> **결론**: "가상이니까 무한 OK" → 틀림. 가상은 **라벨**일 뿐, 데이터는 **물리 RAM/swap 의 진짜 페이지**에 들어간다. Page fault 는 RAM 을 마법으로 만드는 게 아니라, 있는 RAM 을 lazy 매핑하는 메커니즘.

##### Q2: `-Xmx100g` 는 가상 크기? 진짜 크기?

> "16GB 머신에서 `-Xmx100g` 가 시작된다는 게 헷갈림. 저게 JVM 힙 크기 맞지? 가상 주소 크기인가, 진짜 크기인가?"

**짧은 답**: **둘 다.** 시점에 따라 의미가 다름.

`-Xmx100g` = **Java Heap 의 최대 크기**. 그런데 "크기" 가 시점마다 다른 걸 가리킴:

| 시점 | 의미 |
|------|------|
| **JVM 시작 직후** | 가상 주소 공간에 100GB **reserve** (mmap, RAM 거의 안 씀) |
| **실행 중** | 실제 사용량은 **0 ~ 100GB 사이 lazy commit** |
| **상한선** | 물리 메모리도 최대 100GB 까지 사용 가능 (RAM 충분하면) |

**시간 흐름으로 보면**:

```
[T=0] java -Xmx100g Hello
        ↓
[T=1] JVM 시작
        ├── mmap(100GB) 호출
        ├── 가상 주소 100GB 예약 완료
        └── 실제 RAM 사용: ~수십 MB ✓
        ↓
[T=2] 객체 생성 시작
        ├── Eden 페이지 접근 -> Page Fault -> 물리 RAM 할당
        └── 실제 RAM 사용: 100MB
        ↓
[T=3] 객체 많이 생성
        └── 실제 RAM 사용: 5GB
        ↓
[T=4] RAM 16GB 한계 근접
        ├── 오래된 페이지 -> Swap 으로 밀려남
        └── 성능 급락 (Major Fault 빈번)
        ↓
[T=5] Swap 도 가득
        └── OutOfMemoryError 또는 OOM Killer
```

**16GB 머신에서 시작 가능한 이유**:

```
시작 직후:
  가상 주소 공간 :  ████████████████████ 100GB 잡힘
  실제 RAM 사용  :  ▓ ~50MB

가능한 이유 = mmap 이 lazy 라서.
가상 주소 라벨 자체는 거의 공짜.
실제 RAM 은 객체 만들 때 점진적 page fault 로 할당.
```

**"Heap 크기" 의 세 가지 의미 — 가장 헷갈리는 포인트**:

| 이름 | 의미 | 어디서 보나 |
|------|------|-----------|
| **Reserved size** | `-Xmx` 로 잡은 가상 주소 예약 (= 100GB) | `pmap`, NMT 의 reserved |
| **Committed size** | 실제 사용 중인 페이지 (RAM/swap 백킹) | NMT 의 committed |
| **Used size** | 활성 Java 객체가 차지하는 양 (GC 후) | `jcmd GC.heap_info` |

관계: **Used ≤ Committed ≤ Reserved**.
`top` 의 RES (Resident Set Size) ≈ Committed.

**-Xms 와 함께 보면**:

```
-Xms 8g -Xmx 100g
  ↓
시작 시점:
  ├── 가상 주소 100GB reserve     (-Xmx)
  ├── 초기 8GB commit             (-Xms)
  └── RAM 8GB 사용 시작

운영 중:
  ├── 사용량 증가 -> commit 영역 확장 (최대 100GB)
  └── 사용량 감소 -> commit 영역 축소
```

운영 환경에선 `-Xms = -Xmx` 가 흔함 -> 시작 시 전부 commit -> 시작 느리지만 런타임 안정.

**`-XX:+AlwaysPreTouch` 의 진짜 효과**:

```
없음:                    mmap 100GB -> 접근 시점에 commit
+AlwaysPreTouch:         mmap 100GB -> 시작 시 100GB 전체 1바이트씩 touch
                                   -> Page Fault 100GB 분량
                                   -> 다 commit
                                   -> 시작 매우 느림
                                   -> 런타임 매우 안정
```

16GB 머신에서 `-Xmx 100g -XX:+AlwaysPreTouch` -> swap 폭주, 실질적으로 시작 못 함.

> **결론**: `-Xmx100g` = Java Heap 최대 크기. 시작 시점엔 **가상 주소 예약만** (RAM 거의 안 씀). 런타임에 **객체 만들수록 물리 페이지 lazy commit.** 16GB 머신도 시작은 됨 (실제 사용량이 16GB 안에 머무는 한). 진짜 100GB 다 쓰려면 RAM 100GB+ 필요.

##### 두 질문이 사실 같은 이야기

- **Q1 의 답**: 가상 주소는 라벨이라도 데이터는 진짜 RAM 에 들어간다.
- **Q2 의 핵심**: `-Xmx100g` 는 가상 주소 예약. 실제 RAM 은 사용한 만큼만.

같은 원리의 두 측면:

> **"예약은 가상이라 공짜, 사용은 진짜라 비싸다."**

---

## 3. Metaspace — PermGen 의 후계자

### 등장 배경

| | Java 7 까지 (PermGen) | Java 8+ (Metaspace) |
|---|---|---|
| 위치 | **JVM Heap 안** | **Native Memory (OS heap)** |
| 크기 | 고정 (`-XX:PermSize`) | 기본 무제한 (자동 증가) |
| 대표 에러 | `OOM: PermGen space` | `OOM: Metaspace` |
| 동적 클래스 로딩 | 자주 터짐 (Spring, JSP) | 견고함 |

> Spring/Hibernate 같은 프록시 클래스를 잔뜩 만들어내는 환경에서 PermGen 이 자주 터졌고, 이를 native memory 로 옮기면서 해결한 게 Metaspace.

### Metaspace 에 들어가는 것

- **Klass** (클래스 메타데이터 본체)
- Method 구조체 (메서드 시그니처, 바이트코드 위치)
- Constant Pool (상수 풀)
- vtable, itable
- 어노테이션 정보

### Metaspace 에 **안** 들어가는 것 (헷갈리기 쉬움)

- **`java.lang.Class` 객체 (미러)** → **Heap** 에 있음
- **`static` 변수의 값** → **Heap** (Java 8+ 부터. Java 7 까지는 PermGen 이었음)
- 인스턴스 객체 → 당연히 Heap

> 운영 팁: `-XX:MaxMetaspaceSize` 를 안 걸면 native memory 를 끝없이 먹다가 OS 가 OOM killer 로 JVM 을 죽일 수 있다. 운영 환경에선 거의 필수.

---

## 4. Klass — 클래스의 진짜 정체

### Klass 란?

HotSpot JVM 내부의 **C++ 구조체**. 자바 클래스 1개 = Klass 1개. **Metaspace 에 위치**.

들고 있는 정보: 필드 레이아웃, 메서드 테이블, 부모 Klass, 인터페이스, vtable, mirror 포인터.

### `Class` 객체 vs `Klass` (핵심 구분)

| | `java.lang.Class` 객체 | `Klass` |
|---|---|---|
| 언어 | **Java 객체** | **C++ struct** |
| 위치 | **Heap** | **Metaspace** |
| 누가 씀 | 자바 코드 (`MyClass.class`, 리플렉션) | JVM 내부 (GC, JIT, 인터프리터) |
| 별명 | "mirror (거울)" | 실체 |

자바 개발자가 보는 `Class<?>` 는 사실 **거울 객체** 일 뿐이고, 진짜 클래스 정보는 그 뒤의 Klass 에 있다. JDK 가 두 개로 쪼개놓은 이유: 자바 코드가 JVM 내부 구조체를 직접 만지지 못하게 추상화.

### 객체 헤더의 klass pointer — 모든 게 연결되는 지점

```
   [Heap]                            [Metaspace]                     [Heap]
┌──────────────────┐              ┌──────────────────┐          ┌─────────────────┐
│ Java Object      │              │ Klass (C++)      │          │ java.lang.Class │
│ ┌──────────────┐ │              │ ──────────────── │          │ (mirror)        │
│ │ Mark Word    │ │              │ - field layout   │          │ - name          │
│ ├──────────────┤ │              │ - method vtable  │          │ - classLoader   │
│ │ klass ptr ───┼─┼─────────────►│ - super Klass    │          │ - ...           │
│ ├──────────────┤ │              │ - mirror ────────┼─────────►│                 │
│ │ fields       │ │              └──────────────────┘          └─────────────────┘
│ └──────────────┘ │
└──────────────────┘
```

이 한 장이 가장 중요. 모든 Java 객체는 헤더에 **klass pointer (보통 4바이트, 압축됨)** 를 갖고 있고, 이게 Metaspace 의 Klass 를 가리킨다. Klass 는 다시 Heap 의 mirror (`Class` 객체) 를 가리킨다.

### 이 구조로 풀리는 동작들

- **`obj.getClass()`** → klass ptr 따라가 Klass → mirror 필드 → Class 객체 반환
- **메서드 디스패치** (`obj.foo()`) → klass ptr → Klass 의 vtable → 실제 코드
- **`instanceof`** → klass ptr → Klass 의 부모 체인 순회
- **GC 마킹** → klass ptr 보고 객체 크기와 참조 필드 위치 파악

### Compressed Class Pointer

모든 객체가 klass ptr 를 들고 있다 보니 4G 객체 = 32G 메모리 낭비. 그래서 **8바이트 → 4바이트로 압축** 하는 `-XX:+UseCompressedClassPointers` 가 기본 on. Metaspace 와 별도로 **Compressed Class Space** (기본 1G) 가 따로 잡힘.

---

## 5. 프로그램 실행 흐름 — 전체 단계 추적

간단한 예제 하나로 처음부터 끝까지 추적.

```java
public class Hello {
    static int count = 0;
    String name;

    public Hello(String name) { this.name = name; }

    public void greet() {
        count++;
        System.out.println("Hi, " + name);
    }

    public static void main(String[] args) {
        Hello h = new Hello("World");
        h.greet();
    }
}
```

### Phase 0. JVM 프로세스 시작

```
$ java Hello
   ↓
OS 가 fork/exec → java 프로세스 생성
   ↓
JVM 바이너리 (C++ 작성) 가 Text/Data 에 로드됨
   ↓
JVM 이 OS 에 mmap 호출 → 큰 가상 메모리 덩어리 예약
   ├── Java Heap 영역 예약 (-Xmx 만큼)
   ├── Metaspace 영역 예약
   ├── Code Cache 영역 예약
   └── 첫 스레드 (main 스레드) 스택 할당
```

이 시점에 **빈 광장 (영역만 예약)** 이 생성됨. 아직 클래스도, 객체도 없다.

### Phase 1. 부트스트랩 — 시스템 클래스 로딩

```
JVM 이 자기 동작에 필요한 클래스부터 먼저 로드
   ↓
java.lang.Object, String, Class, ClassLoader, Thread ... 의 .class 파일을 읽음
   ↓
각각에 대해:
   ├── Metaspace 에 Klass 생성 (C++ struct)
   └── Heap 에 java.lang.Class 미러 객체 생성
   ↓
서로 포인터로 연결 (Klass ↔ Class)
```

> 닭과 달걀: `java.lang.Class` 의 Klass 를 만들려면 Class 가 필요한데, Class 의 미러를 만들려면 Class 의 Klass 가 필요하다. 그래서 부트스트랩은 특수 경로로 처리된다. 자세한 건 몰라도 됨, "처음에 자기 자신을 끌어올린다" 정도만 기억.

### Phase 2. `Hello` 클래스 로딩 (main 호출 직전)

```
JVM: "main() 실행하려면 Hello 클래스 필요"
   ↓
ClassLoader 가 Hello.class 파일을 디스크에서 읽음
   ↓
바이트코드 파싱 (필드, 메서드, 상수풀 추출)
   ↓
┌────────────────────────────────────────────────────┐
│ [Metaspace]                                        │
│  ┌──────────────────────────────────────────────┐  │
│  │ Hello Klass (newly created)                  │  │
│  │  - field layout: [header | name ref]         │  │
│  │  - method table: greet, <init>, main         │  │
│  │  - super Klass -> Object Klass               │  │
│  │  - const pool ("Hi, ", "World", ...)         │  │
│  │  - mirror ──────────────────────────────────┐│  │
│  └─────────────────────────────────────────────┼┘  │
└────────────────────────────────────────────────┼───┘
                                                 ↓
┌────────────────────────────────────────────────────┐
│ [Heap]                                             │
│  ┌──────────────────────────────────────────────┐  │
│  │ Hello.class  (java.lang.Class mirror object) │  │
│  │  - klass ptr -> Hello Klass                  │  │
│  │  - count = 0    <- static field VALUE here   │  │
│  └──────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────┘
```

핵심: **static 변수의 값은 Class 미러 객체 안에 산다 (Java 8+)**. 즉 **Heap**. Metaspace 가 아님. Java 7 까지는 PermGen 이었던 게 이리로 옮겨졌다.

### Phase 3. `main()` 실행 시작

```
main thread's Stack (top of address space)
┌─────────────────────────────────────────┐
│ main() frame  (pushed)                  │
│  ├─ args        : ref to String[] ──┐   │  <- 참조만 스택에
│  ├─ h           : null (not yet)    │   │
│  └─ return addr                     │   │
└─────────────────────────────────────┼───┘
                                      │
                                      ↓  (points into Heap)
                              ┌────────────────┐
                              │ String[] args  │
                              └────────────────┘
                                  [Heap]
```

지역변수 `h` 의 "**참조 값 자체**" 는 Stack 에 있지만, 가리키는 객체는 Heap 에 있다.

### Phase 4. `new Hello("World")` — 객체 탄생 순간

이 한 줄 안에서 모든 영역이 한 번씩 등장한다.

```
[1] Heap 의 Young Gen (Eden) 에 공간 할당
       ↓
[2] 객체 헤더 초기화
       ├─ Mark Word (락/GC 비트)
       └─ Klass Pointer → Metaspace 의 Hello Klass 를 가리킴 (아래 박스)
       ↓
[3] <init> 생성자 호출
       ↓
[4] Stack 에 <init> 프레임 push
       ↓
[5] this.name = "World"
       ↓
[6] 생성자 종료, <init> 프레임 pop
       ↓
[7] main 의 h 에 새 객체 주소 대입
```

Klass Pointer 가 가리키는 Metaspace 의 Klass:

```
[Metaspace]
┌─────────────────────┐
│ Hello Klass         │
│  - field layout     │   ← 헤더 크기, 필드 오프셋을
│  - method code addr │      이걸 보고 결정
└─────────────────────┘
```

```
[Heap]  (after allocation)
┌────────────────────┐
│ Hello instance     │
│ ┌────────────────┐ │
│ │ Mark Word      │ │
│ ├────────────────┤ │
│ │ klass ptr ─────┼─┼─► Hello Klass         (in Metaspace)
│ ├────────────────┤ │
│ │ name ──────────┼─┼─► "World" String      (in Heap)
│ └────────────────┘ │
└────────────────────┘
```

> "Hello 객체 하나 만들었다" 라는 한 줄에 **Heap 할당 + Stack 프레임 push/pop + Metaspace 의 Klass 조회 + 또 다른 Heap 객체 ("World") 참조** 가 다 일어남.

### Phase 5. `h.greet()` — 메서드 디스패치

```
[1] Stack 에 greet() 프레임 push
       │
       │   메서드 코드는 어디 있나? → 객체로부터 찾아간다
       ↓
[2] h 의 klass ptr 따라감
       ↓
[3] Metaspace 의 Hello Klass 도착
       ↓
[4] Klass 의 vtable 에서 "greet" 슬롯 조회
       ↓
[5] vtable 슬롯이 가리키는 메서드 코드 실행
       │
       ├─ 처음 N 번: 인터프리터가 Metaspace 의 바이트코드를 한 줄씩 해석
       │
       └─ N 번 넘으면: JIT 가 백그라운드에서 컴파일 →
                       Code Cache (native memory) 에 기계어 적재 →
                       이후 호출은 Code Cache 의 네이티브 코드 직접 실행
```

#### greet() 내부에서 일어나는 일

```java
public void greet() {
    count++;                              // Heap 의 Class 미러 객체 필드 update
    System.out.println("Hi, " + name);    // 새 String 객체 → Heap 에 생성
}
```

- `count++` → **Heap (Hello.class 미러 객체) 의 count 필드** 읽기/쓰기
- `"Hi, " + name` → 새 String 인스턴스 → **Heap (Eden) 에 새로 할당**
- `System.out` → static 필드 → `System` 클래스 미러 객체의 필드 → **Heap**
- `println` → 결국 **JNI** 를 통해 OS 의 `write()` syscall 호출 → **native heap 의 IO 버퍼** 사용

### Phase 6. JIT 컴파일 (반복 호출 시)

```
인터프리터: greet() 1000번 실행됨 → "이거 hot 하네"
     ↓
JIT 컴파일러 (C++ 코드, JVM 내부 스레드) 가 백그라운드에서 동작
     ↓
바이트코드 분석 → 최적화 → x86_64 기계어 생성
     ↓
Code Cache (native memory 영역) 에 적재
     ↓
Hello Klass 의 vtable 의 greet 슬롯이 → 인터프리터 진입점에서
                                       → Code Cache 의 기계어 주소로 갱신
     ↓
다음 호출부터 인터프리터 우회, 직접 기계어 실행 (수십~수백 배 빠름)
```

> 이 단계에서 **Code Cache** 가 등장. JIT 컴파일된 코드의 양이 많아지면 Code Cache 도 부족해질 수 있고, `OutOfMemoryError: Compressed class space` 나 Code Cache full 같은 게 터질 수 있음.

### Phase 7. GC

```
Eden 이 꽉 참 (계속 new String 만들었으니)
     ↓
Minor GC 시작
     ↓
[1] GC 루트부터 마킹
     ├── Stack 의 모든 ref (각 스레드의 모든 프레임)
     ├── Class 미러 객체의 static 필드 (Heap)
     └── JNI 글로벌 ref
     ↓
[2] 마킹된 객체를 따라가며 그래프 순회
     │
     │   각 객체의 크기와 참조 필드 위치는 어떻게 아나?
     │       → 객체의 klass ptr 따라가 Metaspace 의 Klass 조회
     │       → Klass 가 "이 객체는 32바이트, 8번째 오프셋에 ref 가 있음" 알려줌
     ↓
[3] 살아남은 객체는 Survivor 로 복사, 나머지 Eden 통째로 비움
     ↓
[4] 일정 횟수 살아남으면 Old Gen 으로 승격
```

> **Klass 가 없으면 GC 도 동작 못 한다.** 객체의 레이아웃 정보가 Klass 에 있기 때문. Heap 과 Metaspace 가 협업하는 결정적 지점.

### Phase 8. 종료 (또는 ClassLoader unload)

- **프로세스 종료**: OS 가 mmap 영역 통째로 회수 → Heap, Metaspace, Code Cache 다 사라짐
- **ClassLoader unload**: 동적으로 로딩된 ClassLoader 가 GC 되면 그 ClassLoader 로 만든 모든 Klass 도 Metaspace 에서 회수됨 (Tomcat hot-redeploy 같은 환경에서 중요)

---

## 6. 전체 흐름을 한 장으로

```
                       ┌──── Stack (per thread) ────┐
                       │ main() frame                │
                       │ greet() frame               │
                       └─────────────┬───────────────┘
                                     │ ref
                                     ↓
   ┌─── Heap ──────────────────────────────────────────────┐
   │                                                       │
   │   ┌─ Hello instance ──┐     ┌─ Hello.class mirror ─┐  │
   │   │ klass ptr ────────┼─┐   │ klass ptr ───────────┼┐ │
   │   │ name ─────────────┼─┼──►│ count = 1            ││ │
   │   └───────────────────┘ │   └──────────────────────┘│ │
   │                         │                           │ │
   │   ┌─ "World" String ─┐  │                           │ │
   │   │ ...              │  │                           │ │
   │   └──────────────────┘  │                           │ │
   └─────────────────────────┼───────────────────────────┼─┘
                             ↓ (klass ptr)        (mirror)
                             ↓                           ↑
   ┌─── Metaspace (native) ──────────────────────────────────┐
   │   ┌─ Hello Klass ──────────┐     ┌─ Class Klass ─────┐  │
   │   │ field layout           │     │ ...               │  │
   │   │ vtable [greet ──────┐  │     └───────────────────┘  │
   │   │ super -> Object Klass│  │                           │
   │   │ mirror ──────────────┼──┼──────────────────────────►│ (to Heap mirror)
   │   └──────────────────────┘  │                           │
   │                             │                           │
   │   ┌─ Object Klass ─────────┐│                           │
   │   │ ...                    ││                           │
   │   └────────────────────────┘│                           │
   └─────────────────────────────┼───────────────────────────┘
                                 ↓ (vtable slot points to)
   ┌─── Code Cache (native) ───────────────────────────────┐
   │   JIT-compiled native code for greet()                │
   │   ┌──────────────────────────────────────┐            │
   │   │ mov rax, [rdi + count_offset]        │            │
   │   │ inc rax                              │            │
   │   │ mov [rdi + count_offset], rax        │            │
   │   │ ...                                  │            │
   │   └──────────────────────────────────────┘            │
   └───────────────────────────────────────────────────────┘
```

---

## 7. 흐름이 보여주는 핵심 인사이트

1. **객체 하나 만들고 메서드 하나 호출하면 모든 영역이 다 등장한다.**
   - Stack (지역변수 + 프레임) + Heap (객체) + Metaspace (Klass) + Code Cache (JIT 코드) + Native (syscall)

2. **klass pointer 는 Heap 과 Metaspace 를 잇는 다리.**
   - 메서드 호출, GC, instanceof, getClass() — 전부 이 포인터를 따라간다.
   - 이 포인터 없으면 JVM 은 객체가 뭔지조차 모름.

3. **"클래스" 라는 추상이 두 영역에 동시에 존재한다.**
   - Metaspace 의 **Klass** = 실체 (JVM 이 쓰는 정보)
   - Heap 의 **Class 미러** = 자바 코드가 만지는 인터페이스
   - 둘은 서로를 가리킴 (양방향 포인터)

4. **static 필드는 Heap, 메서드 코드는 Metaspace, JIT 코드는 Code Cache.**
   - 같은 클래스에 속한 정보지만 영역이 셋으로 흩어져 있음.
   - "이건 어디 있지?" 헷갈릴 때 이 분리 기준으로 찾으면 됨.

5. **GC 가 Heap 만 청소한다고 끝나는 게 아니다.**
   - ClassLoader 가 죽으면 Metaspace 의 Klass 도 같이 정리.
   - JIT 코드가 invalidate 되면 Code Cache 도 정리.
   - 모든 영역이 lifecycle 을 가지고 있음.

---

## 8. 영역별 빠른 참조 표

| 영역 | 위치 | 관리 주체 | 들어가는 것 | 대표 OOM |
|------|------|----------|-------------|---------|
| **Java Heap** | JVM 관리 (mmap) | GC | Java 객체, 배열, Class 미러, static 변수 값 | `Java heap space` |
| **Metaspace** | Native memory | malloc + ClassLoader 단위 회수 | Klass, 메서드, 상수풀, vtable | `Metaspace` |
| **Code Cache** | Native memory | JIT 컴파일러 | JIT 컴파일된 기계어 | `Code Cache full` (경고) |
| **Stack** | 스레드별 가상 주소 | 스레드 생명주기 | 프레임, 지역변수, 참조, 리턴주소 | `StackOverflowError` |
| **Direct Buffer** | Native memory | NIO + GC 트리거 | NIO ByteBuffer | `Direct buffer memory` |
| **Native Heap (그 외)** | OS heap | malloc/free | JNI, GC 자료구조, JVM 내부 | `Native memory allocation` |

---

## 9. 운영 관련 JVM 옵션 빠른 참조

| 옵션 | 의미 |
|------|------|
| `-Xms`, `-Xmx` | Heap 초기/최대 크기 |
| `-Xss` | 스레드당 Stack 크기 |
| `-XX:MaxMetaspaceSize` | Metaspace 최대 크기 (운영 환경 필수) |
| `-XX:CompressedClassSpaceSize` | Compressed Class Space 크기 (기본 1G) |
| `-XX:ReservedCodeCacheSize` | Code Cache 최대 크기 |
| `-XX:MaxDirectMemorySize` | Direct ByteBuffer 한계 |
| `-XX:+UseCompressedClassPointers` | klass ptr 압축 (기본 on) |
| `-XX:+UseCompressedOops` | 객체 참조 압축 (기본 on, <32G heap) |
| `-XX:+AlwaysPreTouch` | 시작 시 Heap 전체 page 미리 터치 (Major Fault 예방) |

---

## 10. 한 줄 요약

> **Native Heap** 은 OS 가 주는 큰 광장. JVM 은 거기서 **Java Heap** 을 따로 임대해 GC 로 관리하고, **Metaspace** 라는 또 다른 native 영역에 클래스 메타데이터인 **Klass** 를 둔다. Heap 의 객체는 헤더의 **klass pointer** 로 Metaspace 의 Klass 를 가리키고, Klass 는 다시 Heap 의 `Class` 미러 객체를 가리킨다 — 이 삼각형이 JVM 메모리 구조의 핵심.

---

## 11. 학습 순서

### 개념 학습 순서
**Native Heap (OS 힙) → JVM Heap (GC 관리) → PermGen (Java 7, 힙 안) → Metaspace (Java 8+, native 로 이동) → Klass (Metaspace 안의 C++ 구조체) → Heap 객체 헤더의 klass pointer → `Class` 미러 객체와의 삼각 연결**

### 실행 흐름 순서
**JVM 프로세스 시작 (영역 예약) → 시스템 클래스 로드 (Klass + Class 미러) → 사용자 클래스 로드 → main 스택 프레임 → new (Heap 할당 + klass ptr 세팅) → 메서드 호출 (klass ptr → Klass → vtable → 코드) → JIT 컴파일 (Code Cache) → GC (Klass 정보 보고 객체 추적) → 종료/언로드**

이 흐름 한 번이 머릿속에 박히면, 나중에 OOM, ClassCastException, NoSuchMethodError, JIT warmup, GC 튜닝 같은 실전 문제 마주쳤을 때 "어느 영역에서 일어난 일인가" 를 바로 짚을 수 있어진다.

---

## ❓ 남은 질문

1. Metaspace OOM 이 나는데 애플리케이션의 "고유 클래스 수" 는 그대로라면 무엇을 의심해야 하나?

   → **답:** ClassLoader 누수다. Metaspace 의 Klass 는 그것을 로드한 ClassLoader 가 GC 될 때만 회수되므로, 핫 리로드나 동적 프록시(CGLIB·Groovy 등)로 같은 클래스가 새 ClassLoader 로 계속 다시 로드되면 옛 Klass 가 안 풀려 무한 증가한다.
2. `-XX:MaxMetaspaceSize` 를 안 걸어 사실상 무제한인데, 그러면 Metaspace 관련 GC 는 대체 언제 트리거되나?

   → **답:** `-XX:MetaspaceSize`(초기 high-water mark)에 도달하면 클래스 언로드를 시도하는 GC 가 유발된다. 회수 결과에 따라 이 임계값이 다음 번엔 상향(또는 하향)되므로, MaxMetaspaceSize 가 없어도 이 임계값 메커니즘으로 주기적 정리는 돈다.
3. `OutOfMemoryError: Compressed class space` 와 `OutOfMemoryError: Metaspace` 는 어떻게 다른가?

   → **답:** Compressed Class Space 는 압축된 klass 포인터로 가리킬 수 있게 별도로 잡는 영역(기본 상한 1G)이고, Klass 본체 외 나머지 메타데이터는 일반 Metaspace 에 들어간다. 클래스가 매우 많으면 Metaspace 에 여유가 있어도 이 1G 가 먼저 차서 전자가 뜬다 — `-XX:CompressedClassSpaceSize` 로 조정한다.
