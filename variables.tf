# =============================================================================
# INPUT VARIABLES
# =============================================================================

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "my_ip" {
  description = "Your IP address for SSH access to management server (CIDR format)"
  type        = string
  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/[0-9]{1,2}$", var.my_ip))
    error_message = "IP address must be in CIDR format (e.g., 203.0.113.25/32)."
  }
}

variable "key_pair_name" {
  description = "Name of existing EC2 Key Pair for SSH access"
  type        = string
}

variable "common_tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "app-server-poc"
    Environment = "poc"
    ManagedBy   = "terraform"
  }
}