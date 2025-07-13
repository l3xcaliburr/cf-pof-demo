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

output "target_group_arn" {
  description = "ARN of the ALB target group for health checks"
  value       = aws_lb_target_group.app.arn
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

# WAF Information
output "waf_web_acl_id" {
  description = "ID of the WAF Web ACL protecting the ALB"
  value       = aws_wafv2_web_acl.alb_protection.id
}

output "waf_web_acl_arn" {
  description = "ARN of the WAF Web ACL for monitoring"
  value       = aws_wafv2_web_acl.alb_protection.arn
}

# Monitoring Information
output "sns_topic_arn" {
  description = "ARN of the SNS topic for management server alerts"
  value       = aws_sns_topic.management_alerts.arn
}

output "cloudwatch_alarms" {
  description = "CloudWatch alarm names for management server monitoring"
  value = {
    instance_stopped = aws_cloudwatch_metric_alarm.management_instance_stopped[*].alarm_name
  }
}