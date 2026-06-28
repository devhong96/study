# ============================================================
# 이 파일: 네트워크 (학습용으로 기본 VPC/서브넷 조회) + 보안그룹
# 실무는 별도 VPC를 만들지만, 여기선 흐름에 집중하려 default VPC 사용.
# ============================================================

# 05에서 본 data 조회 — 만들지 않고 기존 것을 가져옴
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ── ALB용 보안그룹: 인터넷 → ALB (80 공개) ──
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "ALB: allow HTTP from internet"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ── ECS Task용 보안그룹: "ALB에서 오는 트래픽만" 허용 (직접 노출 X) ──
# 핵심: cidr_blocks가 아니라 security_groups로 "ALB 보안그룹"을 출처로 지정 → 최소 권한
resource "aws_security_group" "ecs" {
  name        = "${var.project_name}-ecs-sg"
  description = "ECS tasks: allow traffic only from ALB"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id] # ← ALB 보안그룹만 출처로 허용
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
