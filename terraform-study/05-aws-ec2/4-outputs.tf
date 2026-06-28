# ============================================================
# 이 파일: apply 후 보여줄 결과값
# 🔒=예약어(고정)   ✏️=내 자유(출력이름·값)
# ============================================================

output "instance_id" {                    # 🔒 output / ✏️ "instance_id"(출력 이름)
  description = "생성된 EC2 인스턴스 ID"    # 🔒 description = ✏️ 값
  value       = aws_instance.web.id        # 🔒 value = 🔒 aws_instance + ✏️ web(별명) + 🔒 id(속성)
}

output "public_ip" {                       # 🔒 output / ✏️ "public_ip"
  description = "공인 IP (브라우저로 접속)" # 🔒 / ✏️
  value       = aws_instance.web.public_ip # 🔒 value = 🔒 aws_instance + ✏️ web + 🔒 public_ip
}

output "web_url" {                         # 🔒 output / ✏️ "web_url"
  value = "http://${aws_instance.web.public_ip}" # 🔒 value = ✏️ 값(안에 참조 포함)
}

output "ssh_command" {                     # 🔒 output / ✏️ "ssh_command"
  description = "SSH 접속 예시 (키페어 별도 필요)" # 🔒 / ✏️
  value       = "ssh ec2-user@${aws_instance.web.public_ip}" # 🔒 / ✏️
}
