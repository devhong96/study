# ============================================================
# 이 파일: ALB (Application Load Balancer) — 트래픽을 Task들로 분산
# 그림에서: 사용자 → ALB → ECS Task들
# 구성: ALB → Listener(80) → Target Group → (ECS Service가 Task를 등록)
# ============================================================
resource "aws_lb" "app" {
  name               = "${var.project_name}-alb"
  load_balancer_type = "application"
  internal           = false
  subnets            = data.aws_subnets.default.ids
  security_groups    = [aws_security_group.alb.id]
}

# Target Group: ALB가 트래픽을 보낼 "대상 묶음". Fargate는 IP 타입.
resource "aws_lb_target_group" "app" {
  name        = "${var.project_name}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip" # Fargate(awsvpc)는 IP 단위로 등록

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    matcher             = "200"
  }
}

# Listener: 80포트로 들어온 요청을 Target Group으로 forward
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
