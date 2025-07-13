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