# ============================================================
# 이 파일: apply 후 보여줄 결과값
# ============================================================

output "instance_id" {
  description = "생성된 EC2 인스턴스 ID"
  value       = aws_instance.web.id
}

output "public_ip" {
  description = "공인 IP (브라우저로 접속)"
  value       = aws_instance.web.public_ip
}

output "web_url" {
  value = "http://${aws_instance.web.public_ip}"
}

output "ssh_command" {
  description = "SSH 접속 예시 (키페어 별도 필요)"
  value       = "ssh ec2-user@${aws_instance.web.public_ip}"
}
