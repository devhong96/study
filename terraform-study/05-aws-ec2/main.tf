# ============================================================
# 이 파일: 실제 리소스 정의 (핵심)
# 구성: 최신 Amazon Linux AMI 조회 → 보안그룹 → EC2 인스턴스
# ============================================================

# ── data 소스: 만드는 게 아니라 "조회"하는 블록 ──────────────
# resource = 만든다(INSERT/DELETE) / data = 조회만(SELECT). destroy 해도 data는 안 지워짐.
# AWS가 제공하는 최신 Amazon Linux 2023 이미지(AMI) ID를 찾아온다.
# AMI ID는 리전마다 다르고 수시로 바뀌므로 하드코딩하지 않고 조회한다. (참조: data.aws_ami.<이름>.id)
# ※ data는 plan 시점에 조회되어 그 결과가 plan diff에 반영된다.
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
data "aws_vpc" "ec2_group" {
  default = true
}

# ── 보안그룹: 방화벽 규칙 (서버보다 "먼저" 설계) ─────────────
# ingress=들어오는 규칙, egress=나가는 규칙.
# SSH(22)는 var.my_ip_cidr로 "내 IP만"(최소 권한). HTTP(80)만 0.0.0.0/0 전체 공개.
resource "aws_security_group" "web" {
  name        = "${var.project_name}-sg"
  description = "Allow SSH and HTTP"
  vpc_id      = data.aws_vpc.ec2_group.id # ← data 소스 참조

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

# ── EC2 인스턴스: 실제 서버 (본체, 맨 나중) ─────────────────
# 참조가 곧 설계 순서: 인스턴스가 security_group.web.id를 참조 → "보안그룹 먼저, 서버 나중" 자동 결정
#   data.aws_vpc ─▶ security_group ─▶ instance ◀─ data.aws_ami
resource "aws_instance" "web" {
  ami                    = data.aws_ami.amazon_linux.id # 조회한 AMI 사용 (data 참조)
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.web.id] # ← 위 보안그룹 참조 (이게 순서를 만듦)

  # user_data = 부팅 시 1회 자동 실행 스크립트. 서버에 손으로 안 들어가고 코드로 설정(불변 인프라).
  # <<-EOF ... EOF = 여러 줄 문자열(heredoc).
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
