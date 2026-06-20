# ============================================================
# 이 파일: 실제 리소스 정의 (핵심)
# 구성: 최신 Amazon Linux AMI 조회 → 보안그룹 → EC2 인스턴스
# ============================================================

# ── data 소스: 만드는 게 아니라 "조회"하는 블록 ──────────────
# AWS가 제공하는 최신 Amazon Linux 2023 이미지(AMI) ID를 찾아온다.
# AMI ID는 리전마다 다르고 수시로 바뀌므로 하드코딩하지 않고 조회한다.
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"] # 아마존 공식 이미지만

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# ── 기본 VPC 조회 ───────────────────────────────────────────
# 계정에 기본으로 있는 VPC를 가져와 그 안에 보안그룹을 만든다.
data "aws_vpc" "default" {
  default = true
}

# ── 보안그룹: 방화벽 규칙 ───────────────────────────────────
resource "aws_security_group" "web" {
  name        = "${var.project_name}-sg"
  description = "Allow SSH and HTTP"
  vpc_id      = data.aws_vpc.default.id # ← data 소스 참조

  # 인바운드(들어오는) 규칙
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr] # 변수로 접속 IP 제한
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # 웹은 전체 공개
  }

  # 아웃바운드(나가는) 규칙: 전부 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # 모든 프로토콜
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg"
  }
}

# ── EC2 인스턴스: 실제 서버 ─────────────────────────────────
resource "aws_instance" "web" {
  ami                    = data.aws_ami.amazon_linux.id # 조회한 AMI 사용
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.web.id] # ← 위 보안그룹 참조

  # 부팅 시 자동 실행 스크립트 (nginx 설치 후 실행)
  user_data = <<-EOF
    #!/bin/bash
    dnf install -y nginx
    systemctl enable --now nginx
    echo "<h1>Hello from Terraform on AWS</h1>" > /usr/share/nginx/html/index.html
  EOF

  tags = {
    Name      = "${var.project_name}-web"
    ManagedBy = "terraform"
  }
}
