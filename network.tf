# =============================================================================
# NETWORK INFRASTRUCTURE
# =============================================================================

# VPC Module - Using Coalfire's VPC module
module "vpc" {
  source = "github.com/Coalfire-CF/terraform-aws-vpc-nfw"

  name = "poc-vpc"
  cidr = var.vpc_cidr                                 # VPC CIDR from variables
  azs  = ["${var.aws_region}a", "${var.aws_region}b"] # us-east-1a and us-east-1b

  # Six subnets across two AZs (3 types × 2 AZs each)
  # Subnet assignments defined in terraform.tfvars for security
  public_subnets  = var.public_subnet_cidrs  # Management subnets (internet accessible)
  private_subnets = var.private_subnet_cidrs # Application and Backend subnets

  # Enable internet connectivity
  enable_nat_gateway = true # Allows private subnets to access the internet
  single_nat_gateway = true # Cost-effective for POC

  # DNS settings (DNS resolution for app servers to work properly and communicate with other AWS services.)
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = var.common_tags

  private_subnet_tags = [
    "app-subnet",      # For application subnet in us-east-1a
    "app-subnet",      # For application subnet in us-east-1b  
    "backend-subnet",  # For backend subnet in us-east-1a
    "backend-subnet"   # For backend subnet in us-east-1b
  ]

  public_subnet_suffix = "management-subnet"

  flow_log_destination_type = "cloud-watch-logs"
}

# Random string for unique resource naming
resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
} 