# ── 모듈 출력(return) = 호출자가 module.<이름>.<출력> 으로 꺼냄 ──
output "instance_id" {
  value = aws_instance.web.id
}

output "public_ip" {
  value = aws_instance.web.public_ip
}

output "web_url" {
  value = "http://${aws_instance.web.public_ip}"
}
