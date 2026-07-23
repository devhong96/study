# 학습 로그

> 공부한 날 **"커밋"**하면 여기 기록한다. 최신이 위(연·월·일 모두 역순).
> 구조: `## 연도` → `### 연-월` → `- **월-일 · 주제** — 한 줄 요약. [노트](상대경로)`.
> 상세 내용은 각 노트에. 이 파일은 "언제 뭘 공부했나" 스캔용 목록이다.
> 작성·기록 규칙 → [`CONVENTIONS.md`](CONVENTIONS.md) · 폴더 인덱스 → [`README.md`](README.md)

---

## 2026

### 2026-07
- **07-24 · 노트 남은 질문 전면 보강 + 문서 3분할** — 남은 질문 있던 15개 노트에 1~2줄 답 달기(46개)+섹션 없던 16개 노트에 심화 질문 신설(47개), verifier 반박식 검수로 5건 정정. 곁가지 정정: readOnly=true는 CPU만 절감(스냅샷 유지→메모리 절감은 Hibernate read-only 모드 별도), ZooKeeper ephemeral znode vs etcd lease, 백필(DML)≠gh-ost·pt-osc(DDL). 문서: README를 인덱스로 슬림화하고 LOG·CONVENTIONS 분리.
- **07-22 · DB 옵티마이저 판단 기준** — 비용기반(통계로 최저비용 계획 선택), 인덱스는 매칭 row 비율(보조인덱스 랜덤 재방문 vs 풀스캔 순차, ~20-25% 역전), 조인순서=중간결과 최소화(driving 테이블 작게), 통계 stale→오판·EXPLAIN으로 예상 vs 실제 대조. [노트](<back/260722 DB optimizer는 어떤 기준으로 index 사용 여부와 join 순서를 결정하나요.md>)
- **07-21 · Backpressure 미적용 장애** — 흐름제어 없는 큐(λ>μ→무한증가), OOM→스레드/커넥션 고갈→latency·timeout→retry storm→연쇄장애, Reactive Streams request(n)·rate limit(open loop) vs backpressure(closed loop). [노트](<back/260721 Backpressure를 적용하지 않으면 어떤 장애가 발생할 수 있나요.md>)
- **07-21 · JPA vs MyBatis** — SQL Mapper(직접 SQL·예측100%) vs ORM 명세(SQL 자동생성·영속성 컨텍스트). 갈림길은 도메인 복잡도(→JPA) vs 쿼리 복잡도(→MyBatis), 쓰기=JPA·읽기=MyBatis 혼용도 정당. 성능은 둘 다 JDBC 위라 간판으론 안 갈림. [노트](jpa/jpa-vs-mybatis.md)
- **07-14 · 컨텍스트 스위칭** — 코어(자리) 유한 vs 시분할, 비용 4겹(레지스터·커널·주소공간+TLB·캐시오염), 작업전환≠CS, 모드전환(syscall)≠CS. [노트](internals/context-switching.md)

### 2026-06
- **06-29 · IaC 범위와 경계 + 모듈·멀티환경·원격state** — modules/webserver+envs(dev·prod)+S3 backend, 프로비저닝(Terraform) vs 배포(CI/CD)·운영(CloudWatch) 역할분담, 콘솔 수동변경=drift→plan 감지·import. [노트](infrastructure/iac-scope-and-boundaries.md)
- **06-29 · 테라폼 05 EC2 심화 + 예약어 구분 + ECS 파이프라인** — variables.tf vs terraform.tfvars(환경 복제), 예약어🔒 vs 자유✏️ 판별, ECS CI/CD(CodePipeline→CodeBuild→ECR→ECS→ALB)를 테라폼으로 작성·validate 통과.
- **06-23 · 인덱스 랜덤 I/O·풀스캔 재정리(문답)** — 느린 건 테이블 재방문, 한 데이터=한 정렬만(트레이드오프), 커버링이면 선택도 역전(~25%) 깨짐, 복합인덱스 선두컬럼 규칙. [노트](database/index-random-io-and-covering.md)
- **06-21 · 테라폼 실습 코드 분석(01~05)** — 리소스 블록 해부(타입·논리명·속성), 자동 의존성=참조가 순서를 만듦(DAG), count vs for_each(index drift), module=함수, data vs resource.
- **06-20 · 테라폼 기초와 큰 그림** — 선언형·멱등+tfstate(장부), 블록 6종+사이클(init/plan/apply/destroy), 버전제약 `~>`, credential chain(코드<환경변수<~/.aws<IAM Role). [노트](infrastructure/terraform-fundamentals.md)
- **06-19 · 인덱스의 랜덤 I/O와 커버링** — 순차 vs 랜덤 읽기(random ×4 추정), 보조인덱스 leaf(컬럼순) vs 테이블(PK순) 어긋남→점프, MRR, 선택도 ~20~25%↑면 풀스캔이 쌈. [노트](database/index-random-io-and-covering.md)
- **06-14 · JPA 영속성 컨텍스트 심화** — 2차 캐시 3층·스냅샷, EM·ThreadLocal·트랜잭션 관계, dirty checking, OSIV 커넥션 점유·"엔티티=영속·DTO=표현". [노트](jpa/persistence-context-and-n-plus-one.md)
- **06-14 · JPA 연관관계 & 동시성 심화** — mappedBy=주인 아닌 쪽(거울), 편의 메서드=정합성 보험, 낙관적(@Version·예외→재시도·CAS) vs 비관적(FOR UPDATE·블로킹). [노트](jpa/association-mapping-owner.md)
- **06-14 · 학습 커밋 규칙 셋업** — README 학습 로그 섹션 + AGENTS.md 커밋 규칙 추가, git 저장소 초기화.
- **06-14 · 저장소 구조 정비** — folder/를 단일 루트 저장소로 승격, 트리거 분리(커밋=로컬 / 정리=push까지), 루트 README 추가.
