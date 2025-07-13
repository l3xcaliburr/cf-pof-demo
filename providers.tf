# =============================================================================
# TERRAFORM AND PROVIDER CONFIGURATION
# =============================================================================

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "cf-poc-terraform-state-b91fxp3k"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
  }
}

# AWS Provider Configuration
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.common_tags
  }
} 