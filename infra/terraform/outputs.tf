# outputs.tf

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}


output "backend_alb_dns" {
  description = "Backend ALB DNS name"
  value       = aws_lb.backend.dns_name
}

output "backend_alb_url" {
  description = "Backend ALB URL"
  value       = "http://${aws_lb.backend.dns_name}"
}

output "frontend_public_ip" {
  description = "Frontend instance public IP"
  value       = aws_instance.frontend.public_ip
}

output "frontend_public_dns" {
  description = "Frontend instance public DNS"
  value       = aws_instance.frontend.public_dns
}

output "frontend_url" {
  description = "Frontend base URL"
  value       = "http://${aws_instance.frontend.public_dns}"
}

output "rds_endpoint" {
  description = "RDS endpoint (null when JSON storage is enabled)"
  value       = try(aws_db_instance.main[0].address, null)
}