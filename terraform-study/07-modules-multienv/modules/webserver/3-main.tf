# [흐름 3/4] 모듈 본문 — 05의 "EC2 + 보안그룹"을 변수화한 재사용 틀
#   05와 차이: 하드코딩 대신 var.* 로 받음 → env마다 다른 값으로 재사용
#   🔒=예약어  ✏️=내 자유
data "aws_ami" "al2023" {            # 🔒 data / 🔒 "aws_ami"(타입) / ✏️ "al2023"(별명)
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

data "aws_vpc" "default" {           # 🔒 data / 🔒 "aws_vpc" / ✏️ "default"
  default = true
}

resource "aws_security_group" "web" { # 🔒 resource / 🔒 "aws_security_group" / ✏️ "web"
  name        = "${var.project_name}-sg" # ✏️ 값 (var.project_name = env가 주입)
  description = "Allow SSH and HTTP"
  vpc_id      = data.aws_vpc.default.id

  ingress {                          # 🔒 ingress (SSH, 내 IP만)
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]   # ✏️ var.my_ip_cidr (env가 주입)
  }
  ingress {                          # 🔒 ingress (HTTP, 전체)
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {                           # 🔒 egress (전부 허용)
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg"  # ✏️ 태그 키 Name / ✏️ 값
  }
}

resource "aws_instance" "web" {      # 🔒 resource / 🔒 "aws_instance" / ✏️ "web"
  ami                    = data.aws_ami.al2023.id      # 조회한 AMI (data 참조)
  instance_type          = var.instance_type           # ✏️ env가 주입 (micro/small)
  vpc_security_group_ids = [aws_security_group.web.id]  # 위 보안그룹 참조 → 순서 자동

  # 🔒 user_data = ✏️ 스크립트  (heredoc 시작줄 <<-EOF 엔 주석 금지 — 윗줄에 표기)
  user_data = <<-EOF
    #!/bin/bash
    dnf install -y nginx
    systemctl enable --now nginx
    echo "<h1>${var.project_name}</h1>" > /usr/share/nginx/html/index.html
  EOF

  tags = {
    Name      = "${var.project_name}-web"
    ManagedBy = "terraform"
  }
}
