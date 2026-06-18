# Saga 패턴 정리

> 관련 문서: [Spring: @Async / @EventListener / @TransactionalEventListener 정리](../spring/spring-async-event-listener.md)
> — `@TransactionalEventListener`(AFTER_COMMIT)는 best-effort 작업용이고,
> 결제처럼 **must-succeed(실패하면 원본 데이터가 무효)** 작업은 Saga의 영역이다.

## 0. 한 줄 정의

Saga는 분산 트랜잭션을 ACID 대신
**"각 단계는 로컬 트랜잭션 + 실패하면 그때까지 완료된 단계를 역순으로 보상 거래"** 로 푸는 패턴이다.

- 결제는 ACID로 묶을 수 없다(별도 시스템). 하지만 **되돌릴 수 있다** — 환불/취소/void.
- 결제 게이트웨이가 `authorize`/`capture`/`void`/`refund`를 제공하는 이유가 곧 "보상 거래를 쓰라"는 설계다.

두 가지 스타일이 있다: **오케스트레이션**(중앙 조정자) / **코레오그래피**(이벤트 기반).

---

## 1. 오케스트레이션 (중앙 조정자 방식)

**도메인:** 주문 → ① 재고 예약 → ② 결제 → ③ 배송 등록.
어느 단계든 실패하면 그때까지 완료된 단계를 역순으로 보상.

### 1-1. 공통 추상화

```java
// 각 단계는 정방향(execute)과 보상(compensate)을 쌍으로 가진다
public interface SagaStep {
    void execute(OrderSagaContext ctx);
    void compensate(OrderSagaContext ctx);
    String name();
}
```

```java
// 단계 간에 전달되는 상태. 보상에 필요한 ID들이 실행 도중 채워지므로 가변(mutable)이다
@Getter @Setter
@RequiredArgsConstructor
public class OrderSagaContext {
    private final Long orderId;
    private final Long productId;
    private final int  quantity;
    private final long amount;

    private String paymentId;   // 결제 후 채워짐 → 환불(보상) 때 필요
    private Long   deliveryId;  // 배송 등록 후 채워짐 → 취소(보상) 때 필요
}
```

### 1-2. 각 단계 구현 — 핵심은 "단계마다 로컬 트랜잭션"

```java
@Component
@RequiredArgsConstructor
public class ReserveStockStep implements SagaStep {
    private final StockRepository stockRepository;

    @Override
    @Transactional   // ← 사가 전체가 아니라 '이 단계'만 트랜잭션
    public void execute(OrderSagaContext ctx) {
        Stock stock = stockRepository.findByProductId(ctx.getProductId())
                .orElseThrow(() -> new SagaStepException("재고 레코드 없음"));
        stock.decrease(ctx.getQuantity());   // 재고 부족이면 예외 → 사가 실패 트리거
    }

    @Override
    @Transactional
    public void compensate(OrderSagaContext ctx) {   // 보상: 차감한 재고를 되돌림
        stockRepository.findByProductId(ctx.getProductId())
                .ifPresent(stock -> stock.increase(ctx.getQuantity()));
    }

    @Override public String name() { return "재고 예약"; }
}
```

```java
@Component
@RequiredArgsConstructor
public class PaymentStep implements SagaStep {
    private final PaymentGateway paymentGateway;   // 외부 PG

    @Override
    public void execute(OrderSagaContext ctx) {    // 외부 호출이라 @Transactional 아님
        String paymentId = paymentGateway.charge(ctx.getOrderId(), ctx.getAmount());
        ctx.setPaymentId(paymentId);               // 보상(환불)에 쓸 ID를 컨텍스트에 기록
    }

    @Override
    public void compensate(OrderSagaContext ctx) { // 보상 거래 = 환불 (롤백이 아니라 '상쇄')
        if (ctx.getPaymentId() != null) {
            paymentGateway.refund(ctx.getPaymentId());
        }
    }

    @Override public String name() { return "결제"; }
}
```

```java
@Component
@RequiredArgsConstructor
public class DeliveryStep implements SagaStep {
    private final DeliveryClient deliveryClient;

    @Override
    public void execute(OrderSagaContext ctx) {
        Long deliveryId = deliveryClient.createDelivery(ctx.getOrderId());
        ctx.setDeliveryId(deliveryId);
    }

    @Override
    public void compensate(OrderSagaContext ctx) {
        if (ctx.getDeliveryId() != null) {
            deliveryClient.cancelDelivery(ctx.getDeliveryId());
        }
    }

    @Override public String name() { return "배송 등록"; }
}
```

### 1-3. 오케스트레이터 — 순서대로 실행하고, 실패 시 역순 보상

```java
@Service
@RequiredArgsConstructor
@Slf4j
public class OrderSagaOrchestrator {

    private final ReserveStockStep reserveStockStep;
    private final PaymentStep      paymentStep;
    private final DeliveryStep     deliveryStep;

    public void placeOrder(OrderSagaContext ctx) {
        List<SagaStep> steps = List.of(reserveStockStep, paymentStep, deliveryStep);
        Deque<SagaStep> completed = new ArrayDeque<>();   // 보상용: 완료된 단계 기록

        for (SagaStep step : steps) {
            try {
                step.execute(ctx);
                completed.push(step);
                log.info("[Saga] 완료 ▶ {}", step.name());
            } catch (Exception e) {
                log.warn("[Saga] 실패 ✗ {} → 보상 시작", step.name(), e);
                compensate(completed, ctx);
                throw new SagaFailedException(step.name() + " 단계 실패", e);
            }
        }
        log.info("[Saga] 주문 {} 전체 성공 ✔", ctx.getOrderId());
    }

    private void compensate(Deque<SagaStep> completed, OrderSagaContext ctx) {
        while (!completed.isEmpty()) {
            SagaStep step = completed.pop();   // ArrayDeque + push/pop = 역순(LIFO)
            try {
                step.compensate(ctx);
                log.info("[Saga] 보상 완료 ↩ {}", step.name());
            } catch (Exception e) {
                // 보상 실패는 절대 삼키면 안 됨 → DLQ/재시도/운영자 알림
                log.error("[Saga] 보상 실패 ✗✗ {} — 수동 개입 필요!", step.name(), e);
                // deadLetterService.report(step.name(), ctx, e);
            }
        }
    }
}
```

**실행 흐름 예시 — 결제까지 성공, 배송에서 실패:**

```
▶ 재고 예약   ▶ 결제   ✗ 배송 등록(실패)
                      ↩ 결제 보상(환불)   ↩ 재고 예약 보상(재고 복원)
```

---

## 2. 코레오그래피 (이벤트 기반 방식)

중앙 조정자 없이, **각 서비스가 이벤트를 듣고 → 다음 이벤트를 발행**한다.
실패하면 보상 이벤트를 발행한다.

```java
// 결제 서비스: 재고 예약 완료를 듣고 결제 시도
@Service
@RequiredArgsConstructor
public class PaymentEventHandler {
    private final PaymentGateway gateway;
    private final ApplicationEventPublisher publisher;

    @TransactionalEventListener   // 재고 트랜잭션이 커밋된 후에만
    public void on(StockReservedEvent e) {
        try {
            String paymentId = gateway.charge(e.getOrderId(), e.getAmount());
            publisher.publishEvent(new PaymentCompletedEvent(e.getOrderId(), paymentId));
        } catch (Exception ex) {
            // 실패 → 보상 이벤트 발행 (재고 서비스가 듣고 재고를 되돌림)
            publisher.publishEvent(new PaymentFailedEvent(e.getOrderId()));
        }
    }
}

// 재고 서비스: 결제 실패 보상 이벤트를 듣고 재고 복원
@TransactionalEventListener
public void on(PaymentFailedEvent e) {
    stockService.release(e.getOrderId());   // 보상
}
```

### 오케스트레이션 vs 코레오그래피

| | 오케스트레이션 | 코레오그래피 |
|--|--|--|
| 흐름 파악 | 한 곳에 모여 명확 | 이벤트 따라 흩어짐, 추적 어려움 |
| 결합도 | 조정자가 모든 서비스를 앎 | 서비스 간 느슨함 |
| 적합 | 단계 많고 복잡한 흐름 | 단계 적고 단순한 흐름 |

학습·디버깅·복잡한 주문 흐름에는 **오케스트레이션 권장** — 흐름이 코드 한 곳에 보인다.

---

## 3. 실무 체크리스트 (위 예제에서 생략했지만 반드시 필요)

1. **사가 전체를 `@Transactional`로 묶지 말 것**
   단계별 로컬 트랜잭션이 핵심. 통째로 묶으면 그냥 모놀리식 트랜잭션이고, 외부 호출은 어차피 못 묶인다.

2. **멱등성(idempotency)**
   `execute`/`compensate`가 재시도로 두 번 실행될 수 있다.
   `refund`를 두 번 호출해도 한 번만 환불되도록 멱등 키를 쓸 것.

3. **보상도 실패한다**
   위 코드의 `log.error` 자리는 실무에선 DLQ 적재 + 운영자 알림 + 재시도 스케줄러.
   Saga에서 가장 어려운 부분이다.

4. **사가 상태 영속화**
   위 예제의 `completed` 데크는 인메모리라, 오케스트레이터 프로세스가 중간에 죽으면 보상이 영영 안 돌아간다.
   실무에선 `SagaState` 엔티티(현재 단계, 상태)를 **각 단계 후 DB에 저장**해서,
   재기동 시 미완 사가를 복구한다.

5. **격리성 없음**
   Saga는 ACID의 I(격리성)를 포기한다. 보상 직전의 중간 상태가 다른 트랜잭션에 노출될 수 있다
   (예: 결제됐다가 곧 환불). "semantic lock", "commutative update" 같은 대응책이 필요할 수 있다.

---

## 4. Saga vs Transactional Outbox

| | Saga | Transactional Outbox |
|--|--|--|
| 푸는 문제 | 여러 서비스에 걸친 **비즈니스 트랜잭션** | 단일 트랜잭션과 **메시지 발행의 원자성** |
| 방식 | 단계별 로컬 트랜잭션 + 보상 거래 | 부수효과를 outbox 테이블 INSERT로 바꿔 같은 트랜잭션에 포함, 별도 프로세스가 발행 |
| 관계 | 상호 배타 아님 — Saga의 각 단계 이벤트 발행을 Outbox로 신뢰성 있게 처리할 수 있다 | |
