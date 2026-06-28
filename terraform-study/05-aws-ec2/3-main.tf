# ============================================================
# 이 파일: 실제 리소스 정의 (핵심)
# 구성: 최신 Amazon Linux AMI 조회 → 보안그룹 → EC2 인스턴스
#
# 🔒=예약어(고정: 블록키워드 / 타입(첫 따옴표) / =왼쪽 칸이름 / string·true·var·data)
# ✏️=내 자유(두번째 따옴표 별명 / =오른쪽 값 / tags 키)
# ============================================================

# ── data 소스: 만드는 게 아니라 "조회"하는 블록 ──────────────
# resource = 만든다(INSERT/DELETE) / data = 조회만(SELECT). destroy 해도 data는 안 지워짐.
# AMI ID는 리전·시점마다 바뀌므로 하드코딩 대신 조회. (참조: data.aws_ami.<별명>.id)
data "aws_ami" "amazon_linux" {      # 🔒 data / 🔒 "aws_ami"(타입) / ✏️ "amazon_linux"(별명)
  most_recent = true                 # 🔒 most_recent = 🔒 true
  owners      = ["amazon"]           # 🔒 owners      = ✏️ ["amazon"]  (아마존 공식만)
  filter {                           # 🔒 filter (하위 블록)
    name   = "name"                  # 🔒 name   = ✏️ "name"
    values = ["al2023-ami-*-x86_64"] # 🔒 values = ✏️ ["al2023-ami-*-x86_64"]  (*=와일드카드)
  }
}

# 계정 기본 VPC(사설 네트워크 공간)를 조회 → 그 안에 보안그룹을 만든다
data "aws_vpc" "ec2_group" {         # 🔒 data / 🔒 "aws_vpc"(타입) / ✏️ "ec2_group"(별명)
  default = true                     # 🔒 default = 🔒 true
}

# ── 보안그룹: 방화벽 (서버보다 "먼저"). ingress=들어오기, egress=나가기 ──
resource "aws_security_group" "web" { # 🔒 resource / 🔒 "aws_security_group"(타입) / ✏️ "web"(별명)
  name        = "${var.project_name}-sg"  # 🔒 name        = ✏️ 값 (var.project_name 참조 + "-sg")
  description = "Allow SSH and HTTP"      # 🔒 description = ✏️ "Allow SSH and HTTP"
  vpc_id      = data.aws_vpc.ec2_group.id # 🔒 vpc_id = 🔒 data + ✏️ aws_vpc.ec2_group(조회한 것) + 🔒 id

  ingress {                          # 🔒 ingress  (들어오는 규칙 ①: SSH)
    description = "SSH"              # 🔒 / ✏️
    from_port   = 22                 # 🔒 from_port = ✏️ 22  (22=SSH 포트)
    to_port     = 22                 # 🔒 / ✏️
    protocol    = "tcp"              # 🔒 / ✏️ ("tcp"/"udp"/"-1" 중 택)
    cidr_blocks = [var.my_ip_cidr]   # 🔒 cidr_blocks = ✏️ 값 (var.my_ip_cidr 참조 → 내 IP만)
  }

  ingress {                          # 🔒 ingress  (들어오는 규칙 ②: HTTP)
    description = "HTTP"             # 🔒 / ✏️
    from_port   = 80                 # 🔒 / ✏️ (80=HTTP 포트)
    to_port     = 80                 # 🔒 / ✏️
    protocol    = "tcp"              # 🔒 / ✏️
    cidr_blocks = ["0.0.0.0/0"]      # 🔒 / ✏️ (0.0.0.0/0 = 전 세계 공개)
  }

  egress {                           # 🔒 egress  (나가는 규칙: 전부 허용)
    from_port   = 0                  # 🔒 / ✏️
    to_port     = 0                  # 🔒 / ✏️
    protocol    = "-1"               # 🔒 / ✏️ (-1 = 모든 프로토콜)
    cidr_blocks = ["0.0.0.0/0"]      # 🔒 / ✏️
  }

  tags = {                           # 🔒 tags
    Name = "${var.project_name}-sg"  # ✏️ Name (태그 키도 내 자유!) = ✏️ 값
  }
}

# ── EC2 인스턴스: 본체(맨 나중). 참조가 곧 순서: 보안그룹 먼저, 서버 나중 ──
#   data.aws_vpc ─▶ security_group ─▶ instance ◀─ data.aws_ami
resource "aws_instance" "web" {      # 🔒 resource / 🔒 "aws_instance"(타입) / ✏️ "web"(별명)
  ami                    = data.aws_ami.amazon_linux.id # 🔒 ami = 🔒 data + ✏️ 별명 + 🔒 id
  instance_type          = var.instance_type            # 🔒 instance_type = 🔒 var + ✏️ 변수이름
  vpc_security_group_ids = [aws_security_group.web.id]   # 🔒 칸 = ✏️ web(별명) + 🔒 id

  # 🔒 user_data = ✏️ 스크립트 내용  (※ heredoc <<-EOF 시작 줄엔 주석 못 붙임 — 윗줄에 표기)
  # user_data = 부팅 시 1회 실행 스크립트(heredoc). 안쪽은 bash라 테라폼 예약어 아님.
  user_data = <<-EOF
    #!/bin/bash
    dnf install -y nginx
    systemctl enable --now nginx
    echo "<h1>Hello from Terraform on AWS</h1>" > /usr/share/nginx/html/index.html
  EOF

  tags = {                           # 🔒 tags
    Name      = "${var.project_name}-web" # ✏️ 태그 키 = ✏️ 값
    ManagedBy = "terraform"               # ✏️ / ✏️
  }
}
