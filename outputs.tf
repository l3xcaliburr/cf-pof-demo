# =============================================================================
# OUTPUTS
# =============================================================================

# Network Information
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets (management and ALB)"
  value       = module.vpc.public_subnets
}

output "management_subnet_id" {
  description = "ID of the management subnet"
  value       = values(module.vpc.public_subnets)[0]
}

output "alb_subnet_id" {
  description = "ID of the ALB subnet"
  value       = values(module.vpc.public_subnets)[1]
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.vpc.private_subnets
}

# Management Server
output "management_server_ip" {
  description = "Public IP of the management server"
  value       = module.management_server.instance_id[0]
}

output "management_server_private_ip" {
  description = "Private IP of the management server"
  value       = module.management_server.primary_private_ip_addresses[0]
}

# Load Balancer
output "load_balancer_dns" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "load_balancer_url" {
  description = "URL to access the app application"
  value       = "http://${aws_lb.main.dns_name}"
}

# Auto Scaling Group
output "asg_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.app.name
}

# Security Groups
output "management_sg_id" {
  description = "ID of the management security group"
  value       = module.management_sg.id
}

output "app_sg_id" {
  description = "ID of the application security group"
  value       = module.app_sg.id
}

output "alb_sg_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb_sg.id
}