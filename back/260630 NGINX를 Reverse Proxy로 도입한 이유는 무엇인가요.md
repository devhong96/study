# 260630 NGINX를 Reverse Proxy로 도입한 이유는 무엇인가요?

[오늘의 백엔드 질문]
NGINX를 Reverse Proxy로 도입한 이유는 무엇인가요?

포트폴리오나 이력서에 “NGINX를 활용해 Reverse Proxy 구성”이라고 적는 경우가 많습니다.
그런데 면접에서는 생각보다 자주 이렇게 물어봅니다.

“왜 굳이 NGINX를 앞에 뒀나요?”

이 질문은 단순히 NGINX 설정을 해봤는지보다,
클라이언트 요청이 서버까지 도달하는 흐름과 운영 환경에서 Reverse Proxy가 어떤 역할을 하는지 이해하고 있는지 확인하는 질문에 가깝습니다.

같이 체크해보면 좋은 포인트는 아래와 같습니다.

클라이언트 요청을 내부 WAS로 전달하는 진입점 역할
여러 애플리케이션 서버로 요청을 분산하는 Load Balancing
SSL/TLS 종료 지점으로 활용 가능
정적 파일 처리, 압축, 캐싱 등으로 WAS 부하 감소
timeout, header, body size, rate limit 등 요청 제어 가능
꼬리질문으로는 이런 질문이 이어질 수 있습니다.

ㄴ> Reverse Proxy와 Forward Proxy의 차이는 무엇인가요?
ㄴ> NGINX와 WAS가 직접 요청을 받는 구조는 어떤 차이가 있나요?
ㄴ> NGINX에서 upstream 설정은 어떻게 하나요?
ㄴ> NGINX 장애가 나면 전체 서비스에 어떤 영향이 있나요?
ㄴ> 로드밸런서와 NGINX를 같이 쓰는 경우 각각의 역할은 무엇인가요?

급하게 면접이 잡히셨나요?
ㄴ> [https://www.incu-career.kr/backend-expected-question-report](https://www.incu-career.kr/backend-expected-question-report)
기술면접대비 과정: [https://www.incu-career.kr/interview](https://www.incu-career.kr/interview)
백엔드 과제전형 대비 과정:
[https://www.incu-career.kr/backend-assignment](https://www.incu-career.kr/backend-assignment)

---

## 답변

> **한 줄 핵심**: WAS가 겸하면 비효율적이거나 위험한 책임들(분산, TLS, 정적 파일, slow client, 요청 제어, 노출면)을 — 이벤트 기반이라 그 일에 구조적으로 유리한 전용 계층으로 분리하기 위해서다.

### 면접 답변 (구술용)

WAS를 직접 노출하지 않고 NGINX를 앞에 두면 트래픽 제어와 부하 분산, 보안 책임을 WAS에서 분리할 수 있기 때문입니다. 구체적으로 다섯 가지입니다. 첫째, 단일 진입점이자 로드밸런서 역할 — 스케일아웃을 하려면 요청을 나눠줄 지점이 필요한데 그게 Reverse Proxy이고, 무중단 배포 시 트래픽 전환 스위치이기도 합니다. 둘째, TLS 종료 — 인증서 관리를 한곳으로 모으고 핸드셰이크 비용을 WAS에서 떼어냅니다. 셋째, 정적 파일 서빙·압축·캐싱으로 WAS 부하 감소 — NGINX는 이벤트 기반이라 적은 메모리로 수만 커넥션을 유지할 수 있어서 이런 대량 단순 작업에 구조적으로 유리합니다. 넷째, 요청 제어 — timeout, body 크기 제한, rate limit을 코드 배포 없이 설정으로 조절하고, 특히 느린 클라이언트와의 커넥션을 NGINX가 대신 물어줘서 WAS 스레드가 오래 잠기지 않게 합니다. 다섯째, 보안 — WAS 포트를 외부에 노출하지 않고 공격 표면을 한곳으로 모읍니다. 요약하면 "그 일을 더 잘하는 계층에 그 일을 맡긴 것"입니다.

### 원리 이해 (왜 그런가)

**책임 분리표 (왜 NGINX가 그 일을 더 잘하나):**

| 책임 | WAS가 직접 하면 | NGINX가 하면 (근거) |
|------|----------------|---------------------|
| 로드밸런싱 | 진입점 분산 불가 (인스턴스가 여럿인데 누가 나누나?) | upstream으로 round-robin/least_conn 분산 + 배포 시 전환점 |
| TLS | 인스턴스마다 인증서 관리 + 핸드셰이크 CPU 부담 | 종료 지점 1곳 — 인증서 관리 집중, 내부는 단순화 |
| 정적 파일 | 동적 로직용의 비싼 WAS 스레드 낭비 | 이벤트 루프로 저비용 대량 서빙 + sendfile 등 커널 최적화 |
| slow client | 느린 클라이언트 수만큼 WAS 스레드 잠김 | 요청을 버퍼링해 완성됐을 때만 WAS에 전달 — WAS는 짧게 일하고 반납 |
| 요청 제어 | 코드 수정·배포 필요 | limit_req, timeout, 헤더 제어를 설정으로 |

**핵심 구조 근거**: NGINX는 워커 프로세스 몇 개가 각각 이벤트 루프(epoll)를 돌리는 구조라, 커넥션당 스레드를 쓰는 전통 WAS 모델과 달리 "많은 커넥션을 오래 물고 있는 일"이 저렴합니다. Redis가 빠른 이유(260615)와 같은 계열의 설계입니다.

**upstream 설정 예시:**

```nginx
upstream backend {
    least_conn;                                      # 분산 알고리즘 (기본 round-robin)
    server app1:8080 weight=2;
    server app2:8080 max_fails=3 fail_timeout=10s;   # passive health check
}
server {
    location / { proxy_pass http://backend; }
}
```

### 꼬리질문 Q&A

**Q. Reverse Proxy와 Forward Proxy의 차이는?**
→ **누구를 대리하느냐가 기준이다.**
Forward Proxy는 클라이언트 쪽에 서서 클라이언트를 대신해 외부로 나갑니다 — 서버는 프록시만 보이므로 사내망 통제나 우회에 쓰입니다. Reverse Proxy는 서버 쪽에 서서 클라이언트 요청을 받아 내부 서버로 전달합니다 — 클라이언트는 뒤의 서버 구성을 모르므로 은닉·분산·제어가 가능해집니다.

**Q. WAS가 직접 요청을 받는 구조와의 차이는?**
→ **TLS·정적 파일·slow client·rate limit을 전부 WAS가 감당하게 되고, 스케일아웃 시 진입점 문제가 풀리지 않는다.**
소규모 단일 서버라면 직접 노출도 가능합니다. 하지만 인스턴스가 2대가 되는 순간 분산 지점이 필요하고, 트래픽이 커지는 순간 slow client와 정적 파일이 WAS 스레드를 잠식하기 시작합니다 — 프록시 계층이 "언젠가 반드시 필요해지는" 이유입니다.

**Q. upstream 설정은 어떻게 하나요?**
→ **위 예시처럼 upstream 블록에 서버 목록과 분산 알고리즘을 정의하고 proxy_pass로 연결한다.**
max_fails/fail_timeout은 실패가 누적된 서버를 일정 시간 제외하는 passive health check입니다 — 요청을 흘려보내면서 감지하는 방식이라, 주기적으로 미리 찔러보는 active health check와 다릅니다. active는 오픈소스 NGINX에는 없고 NGINX Plus 기능이라, 오픈소스에서는 앞단 LB나 별도 구성으로 보완합니다.

**Q. NGINX 장애가 나면 전체 서비스에 어떤 영향이 있나요?**
→ **단일 NGINX면 모든 트래픽의 관문이므로 SPOF — 전체 중단이다.**
그래서 NGINX를 이중화하고 keepalived(VRRP)로 VIP를 넘기는 failover를 구성하거나, 클라우드에서는 관리형 로드밸런서(ALB/NLB)를 앞단에 둬서 NGINX 자체를 다중화합니다. "프록시 도입 = 새로운 SPOF 후보 추가"라는 인식과 대비책까지 말해야 답이 완결됩니다.

**Q. 로드밸런서와 NGINX를 같이 쓰면 각각의 역할은?**
→ **앞단 관리형 LB는 가용영역 간 분산·헬스체크·NGINX 인스턴스 다중화를, NGINX는 L7 세밀 제어(경로 라우팅, TLS 종료, 캐싱, rate limit)를 맡는 계층 분리다.**
"LB는 살아있는 NGINX를 고르고, NGINX는 요청을 이해하고 다듬어 WAS로 보낸다"로 정리할 수 있습니다.

### 🌱 심화 키워드
- **C10K 문제** — 커넥션당 스레드 모델의 한계와 이벤트 기반 서버 등장의 배경
- **TLS termination / TLS passthrough** — 어디서 암호화를 풀 것인가의 선택지
- **proxy buffering** — slow client 방어의 실체 (끄면 스트리밍은 되지만 보호가 사라짐)
- **limit_req (leaky bucket)** — NGINX rate limit의 알고리즘
- **keepalived / VRRP / VIP** — 프록시 자체의 고가용성 구성

### 🔗 참고 자료
- NGINX 공식 문서 — "NGINX Reverse Proxy", "HTTP Load Balancing" 가이드
- nginx.org 문서 — ngx_http_upstream_module (max_fails 등 파라미터 정의)

### ❓ 더 파볼 질문
- **NGINX의 worker 프로세스 모델은 Redis의 단일 스레드 모델과 뭐가 다른가?**
  ↳ NGINX는 master + 코어 수만큼의 worker 프로세스를 두고 각 worker가 독립 이벤트 루프를 돌린다 — 멀티코어를 프로세스 단위로 활용하는 구조다. Redis는 명령의 원자성을 위해 실행 루프를 하나로 유지한다(260701). "이벤트 루프"라는 재료는 같은데 원자성 요구 때문에 배치가 달라진 사례로 묶어 이해하면 좋다.
- **L4 로드밸런서와 L7 로드밸런서는 어떻게 다른가?**
  ↳ L4는 TCP/IP 수준에서 IP:포트만 보고 분산한다 — 내용을 안 보니 빠르고 단순하다. L7은 HTTP를 이해해서 경로·헤더·쿠키 기반 라우팅이 가능하다 — 기능이 많은 대신 파싱 비용이 있다. 그래서 "L4로 크게 나누고 L7로 세밀하게"라는 계층 구성이 일반적이다.
- **proxy buffering을 끄면 무슨 일이 생기나?**
  ↳ 업스트림 응답을 버퍼에 모으지 않고 즉시 클라이언트로 흘린다 — SSE/스트리밍 응답에는 필요하지만, 느린 클라이언트가 응답을 다 받을 때까지 WAS 커넥션이 함께 잡혀 있게 되어 slow client 방어가 사라진다. 스트리밍 경로에만 선별적으로 끄는 것이 원칙이다.
