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