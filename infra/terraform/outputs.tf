output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "backend_public_ip" {
  description = "Backend instance public IP"
  value       = aws_instance.backend.public_ip
}

output "backend_public_dns" {
  description = "Backend instance public DNS"
  value       = aws_instance.backend.public_dns
}

output "backend_url" {
  description = "Backend base URL"
  value       = "http://${aws_instance.backend.public_dns}"
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