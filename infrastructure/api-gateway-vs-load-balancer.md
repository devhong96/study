# API Gateway vs Load Balancer

둘 다 트래픽 앞단(진입점)에 서지만 **관심사가 다르다.** LB는 "분산", API Gateway는 "API 요청 제어/관리"가 본질이다.

## 한 줄 비교

| | Load Balancer | API Gateway |
|---|---|---|
| 핵심 목적 | **트래픽 분산** (가용성·확장성) | **API 요청 관리/제어** (단일 진입점) |
| 동작 계층 | 주로 L4(TCP/UDP), L7(HTTP) | L7 (HTTP/API 의미 단위) |
| 보는 단위 | 패킷/커넥션 또는 요청 | "어떤 API인가" (경로·메서드·인증) |
| 뒤단 구성 | **같은** 역할의 인스턴스 N개 | **서로 다른** 역할의 서비스들 |
| 관심사 | "어느 서버로 보낼까" (which) | "받아도 되나, 어떻게 처리할까" (what/how) |

## Load Balancer — "분산"이 본질

동일한 역할을 하는 **여러 서버 인스턴스에 트래픽을 골고루** 뿌리는 게 목적.

- 분산 알고리즘: 라운드 로빈, least-connection, IP 해시, 가중치(weighted) 등
- 헬스 체크로 죽은 인스턴스 자동 제외
- 목표: **고가용성(HA) + 수평 확장(scale-out)**
- LB 입장에서 뒤의 서버 N대는 모두 **동일한 놈** → 단지 부하를 나눌 뿐
- 예: AWS ALB/NLB, Nginx, HAProxy

## API Gateway — "제어/관문"이 본질

클라이언트와 백엔드(특히 MSA의 여러 서비스) 사이의 **단일 진입점**이 되어 공통 관심사를 처리. 라우팅은 여러 기능 중 하나일 뿐.

- **인증/인가** (JWT 검증, API Key)
- **Rate limiting / Throttling** (사용량 제한)
- **라우팅**: `/orders/*` → 주문 서비스, `/users/*` → 유저 서비스 (서로 **다른** 서비스로)
- 요청/응답 변환, 프로토콜 변환 (REST ↔ gRPC 등)
- 로깅, 모니터링, 캐싱
- 예: AWS API Gateway, Kong, Spring Cloud Gateway

## 핵심 차이 한 방에

> **LB**: 같은 서비스 인스턴스 N개 중 하나로 → "**누구한테**(which instance)"
> **API Gateway**: 요청 내용을 보고 적절한 서비스로 + 공통 처리 → "**무엇을·어떻게**(what/how)"

## 둘은 대체재가 아니라 보완재

실무에서는 보통 겹쳐서 배치한다.

```
Client
  ↓
[Load Balancer]         ← 트래픽 분산, TLS 종료
  ↓
[API Gateway 인스턴스들]  ← 인증 / rate limit / 라우팅
  ↓
[각 마이크로서비스]       ← 각 서비스 앞에 또 LB가 있을 수도
```

## 헷갈리는 지점

L7 LB(예: ALB)도 경로 기반 라우팅(`/api/*`)을 지원해서 기능이 일부 겹친다. 선택 기준:

- 인증·rate limit·API 키·요청 변환 같은 **API 관리 기능**이 필요 → **API Gateway**
- 그냥 똑같은 서버 여러 대에 **부하만 나누면 됨** → **Load Balancer**

---

## ❓ 남은 질문

1. API Gateway 자체가 단일 장애점(SPOF)이 되지 않으려면 어떻게 구성하나?

   → **답:** Gateway를 여러 인스턴스로 띄우고 그 앞에 LB를 두어 이중화한다. 노트의 배치도처럼 LB → Gateway 인스턴스들 구조가 되며, Gateway는 인증·라우팅 상태를 외부(토큰·설정 저장소)에 두어 stateless로 만들수록 확장이 쉽다.

2. MSA에서 서비스가 많아질 때 단일 API Gateway가 병목이 되면 어떤 대안이 있나?

   → **답:** 기능별로 Gateway를 나누는 방식(예: BFF, Backend For Frontend — 클라이언트 종류별 전용 게이트웨이)이나, 각 서비스에 사이드카 프록시를 붙이는 서비스 메시(예: Istio)로 공통 관심사를 분산 처리하는 방법이 있다.

3. L7 LB(ALB)로도 경로 라우팅이 되는데, 굳이 API Gateway를 두는 결정적 기준은?

   → **답:** 인증/인가, rate limiting, 요청·응답 변환, API 키 관리 같은 애플리케이션 계층 정책이 필요할 때다. 단순 경로 분기와 부하 분산만 필요하면 L7 LB로 충분하다.
