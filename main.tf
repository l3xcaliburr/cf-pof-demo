# =============================================================================
# AWS POC Infrastructure - app Server with Network Segmentation
# =============================================================================

# VPC Module - Using Coalfire's VPC module
module "vpc" {
  source = "github.com/Coalfire-CF/terraform-aws-vpc-nfw"

  name = "poc-vpc"
  cidr = "10.1.0.0/16"                                # As required by the POC
  azs  = ["${var.aws_region}a", "${var.aws_region}b"] # us-east-1a and us-east-1b

  # Six subnets across two AZs (3 types × 2 AZs each)
  # AZ-a: Management(10.1.1.0/24), Application(10.1.2.0/24), Backend(10.1.3.0/24)
  # AZ-b: Management(10.1.4.0/24), Application(10.1.5.0/24), Backend(10.1.6.0/24)
  public_subnets  = ["10.1.1.0/24", "10.1.4.0/24"]                               # Management subnets (internet accessible)
  private_subnets = ["10.1.2.0/24", "10.1.5.0/24", "10.1.3.0/24", "10.1.6.0/24"] # Application and Backend subnets

  # Enable internet connectivity
  enable_nat_gateway = true # Allows private subnets to access the internet
  single_nat_gateway = true # Cost-effective for POC

  # DNS settings (DNS resolution for app servers to work properly and communicate with other AWS services.)
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = var.common_tags


  private_subnet_tags = [
    "app-subnet",      # For 10.1.2.0/24 in us-east-1a
    "app-subnet",      # For 10.1.5.0/24 in us-east-1b  
    "backend-subnet",  # For 10.1.3.0/24 in us-east-1a
    "backend-subnet"   # For 10.1.6.0/24 in us-east-1b
  ]


  public_subnet_suffix = "management-subnet"

  flow_log_destination_type = "cloud-watch-logs"
}

resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# =============================================================================
# SECURITY GROUPS
# =============================================================================

# Management Server Security Group
module "management_sg" {
  source = "github.com/Coalfire-CF/terraform-aws-securitygroup"

  name        = "management-sg"
  description = "Security group for management server"
  vpc_id      = module.vpc.vpc_id

  ingress_rules = {
    ssh = {
      description = "SSH from authorized IP" # This is the only rule that allows SSH access to the management server
      ip_protocol = "tcp"
      from_port   = "22"
      to_port     = "22"
      cidr_ipv4   = var.my_ip # Single IP address for SSH access
    }
  }

  egress_rules = {
    all_outbound = {
      description = "All outbound traffic"
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  tags = merge(var.common_tags, {
    Purpose = "management"
  })
}

# Application Load Balancer Security Group
resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTP from internet" # Allows HTTP traffic from the internet
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound traffic" # Allows all outbound traffic
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name    = "alb-sg"
    Purpose = "load-balancer"
  })
}

# Application Server Security Group
module "app_sg" {
  source = "github.com/Coalfire-CF/terraform-aws-securitygroup"

  name        = "app-servers-sg"
  description = "Security group for application servers"
  vpc_id      = module.vpc.vpc_id

  ingress_rules = {
    ssh_from_mgmt = {
      description                  = "SSH from management server" # Allows SSH access from the management server as per requirements
      ip_protocol                  = "tcp"
      from_port                    = "22"
      to_port                      = "22"
      referenced_security_group_id = module.management_sg.id
    }
    http_from_alb = {
      description                  = "HTTP from ALB" # Allows HTTP traffic from the ALB as per requirements
      ip_protocol                  = "tcp"
      from_port                    = "80"
      to_port                      = "80"
      referenced_security_group_id = aws_security_group.alb_sg.id
    }
  }

  egress_rules = {
    all_outbound = {
      description = "All outbound traffic" # Allows all outbound traffic
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  tags = merge(var.common_tags, {
    Purpose = "application"
  })
}

# =============================================================================
# DATA SOURCES
# =============================================================================

# Get latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# =============================================================================
# MANAGEMENT SERVER
# =============================================================================

module "management_server" {
  source = "github.com/Coalfire-CF/terraform-aws-ec2"

  name              = "management-server"
  instance_count    = 2 # High availability considering we have two AZs
  ami               = data.aws_ami.amazon_linux.id
  ec2_instance_type = "t2.micro"
  ec2_key_pair      = var.key_pair_name
  subnet_ids        = [values(module.vpc.public_subnets)[0]]
  vpc_id            = module.vpc.vpc_id
  root_volume_size  = 10
  ebs_kms_key_arn   = null
  ebs_optimized     = false # t2.micro doesn't support EBS optimization
  global_tags       = var.common_tags

  associate_public_ip = true # Allows the management server to be accessible from the internet

  # Use existing security group
  create_security_group      = false
  additional_security_groups = [module.management_sg.id]

  tags = merge(var.common_tags, {
    Purpose = "management"
  })
}

# =============================================================================
# WAF WEB ACL FOR ALB PROTECTION
# =============================================================================

resource "aws_wafv2_web_acl" "alb_protection" {
  name        = "poc-alb-waf"
  description = "WAF protection for POC Application Load Balancer"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # Common rule set for OWASP Top 10 protection
  rule {
    name     = "poc-common-rules"
    priority = 1

    override_action {
      count {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"

        rule_action_override {
          action_to_use {
            count {}
          }
          name = "SizeRestrictions_QUERYSTRING"
        }

        rule_action_override {
          action_to_use {
            count {}
          }
          name = "NoUserAgent_HEADER"
        }

        scope_down_statement {
          geo_match_statement {
            country_codes = ["US", "CA"]
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "poc-common-rules-metric"
      sampled_requests_enabled   = true
    }
  }

  # Known bad inputs protection
  rule {
    name     = "poc-bad-inputs-rules"
    priority = 2

    override_action {
      count {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "poc-bad-inputs-metric"
      sampled_requests_enabled   = true
    }
  }

  # Rate limiting to prevent abuse
  rule {
    name     = "poc-rate-limit-rule"
    priority = 3

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "poc-rate-limit-metric"
      sampled_requests_enabled   = true
    }
  }

  tags = merge(var.common_tags, {
    Name    = "poc-alb-waf"
    Purpose = "web-protection"
  })

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "poc-alb-waf-metric"
    sampled_requests_enabled   = true
  }
}

# Associate WAF with ALB
resource "aws_wafv2_web_acl_association" "alb_waf_association" {
  resource_arn = aws_lb.main.arn
  web_acl_arn  = aws_wafv2_web_acl.alb_protection.arn
}

# =============================================================================
# MANAGEMENT SERVER HEALTH MONITORING
# =============================================================================

# SNS Topic for CloudWatch Alarms
resource "aws_sns_topic" "management_alerts" {
  name = "poc-management-server-alerts"

  tags = merge(var.common_tags, {
    Name    = "poc-management-alerts"
    Purpose = "monitoring"
  })
}

# SNS Topic Subscription (only if email is provided)
resource "aws_sns_topic_subscription" "email_alerts" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.management_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# CloudWatch Alarms for Management Server Instance State (Simple POC monitoring)
resource "aws_cloudwatch_metric_alarm" "management_instance_stopped" {
  count = length(module.management_server.instance_id)

  alarm_name          = "poc-management-server-${count.index + 1}-stopped"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "0"
  alarm_description   = "ALERT: Management server ${count.index + 1} has been stopped or is failing - POC Demo"
  alarm_actions       = [aws_sns_topic.management_alerts.arn]
  ok_actions          = [aws_sns_topic.management_alerts.arn]
  treat_missing_data  = "breaching"

  dimensions = {
    InstanceId = module.management_server.instance_id[count.index]
  }

  tags = merge(var.common_tags, {
    Name    = "poc-management-server-${count.index + 1}-stopped"
    Purpose = "poc-demo-monitoring"
  })
}

# =============================================================================
# APPLICATION LOAD BALANCER
# =============================================================================

resource "aws_lb" "main" {
  name               = "poc-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = values(module.vpc.public_subnets) # Both public subnets

  enable_deletion_protection = false

  tags = merge(var.common_tags, {
    Name = "poc-alb"
  })
}

resource "aws_lb_target_group" "app" {
  name     = "app-servers-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = merge(var.common_tags, {
    Name = "app-servers-tg"
  })
}

resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# =============================================================================
# AUTO SCALING GROUP
# =============================================================================

resource "aws_launch_template" "app" {
  name_prefix   = "app-server-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"
  key_name      = var.key_pair_name

  vpc_security_group_ids = [module.app_sg.id]

  # Install Apache on the app server
  user_data = base64encode(templatefile("${path.module}/user-data/install-apache.sh", {
    region = var.aws_region
  }))

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.common_tags, {
      Name = "app-server"
      Type = "application"
    })
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "app" {
  name                      = "app-servers-asg"
  vpc_zone_identifier       = [values(module.vpc.private_subnets)[0], values(module.vpc.private_subnets)[1]] # Application subnets in both AZs
  target_group_arns         = [aws_lb_target_group.app.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300

  min_size         = 2
  max_size         = 6
  desired_capacity = 2

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "app-server-asg"
    propagate_at_launch = false
  }

  dynamic "tag" {
    for_each = var.common_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}