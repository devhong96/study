# ============================================================
# 이 파일: ECS — 컨테이너 실행 (Cluster → Task Definition → Service)
# 그림에서: ECR 이미지를 pull해서 Task(컨테이너)로 실행, ALB에 연결
# ============================================================

# 컨테이너 로그 보관함
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 7
}

# Cluster: Task들이 도는 논리적 공간
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"
}

# Task Definition: "무엇을 어떻게 실행할지"의 설계도 (이미지·CPU·메모리·포트·로그)
resource "aws_ecs_task_definition" "app" {
  family                   = var.project_name
  requires_compatibilities = ["FARGATE"] # 서버리스 (EC2 관리 불필요)
  network_mode             = "awsvpc"
  cpu                      = "256" # 0.25 vCPU
  memory                   = "512" # 0.5 GB
  execution_role_arn       = aws_iam_role.ecs_execution.arn

  # 컨테이너 정의는 JSON. terraform의 jsonencode로 HCL→JSON 변환
  container_definitions = jsonencode([
    {
      name      = var.project_name
      image     = "${aws_ecr_repository.app.repository_url}:latest" # ← ECR 이미지 참조
      essential = true
      portMappings = [
        { containerPort = var.container_port, protocol = "tcp" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

# Service: "Task를 몇 개 유지하고, ALB에 어떻게 연결할지"
resource "aws_ecs_service" "app" {
  name            = "${var.project_name}-svc"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true # 기본 서브넷이 public이라 이미지 pull 위해 필요
  }

  # ALB Target Group에 Task를 등록 → ALB가 트래픽 분산
  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = var.project_name
    container_port   = var.container_port
  }

  # Listener가 준비된 뒤 서비스 생성 (참조가 없어 명시적 의존성 지정)
  depends_on = [aws_lb_listener.http]

  # ★ 배포는 CodePipeline(ECS deploy)이 task_definition을 갱신하므로,
  #   테라폼은 그 변경을 다시 되돌리지 않도록 무시한다. (도구 간 소유권 분리)
  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }
}
