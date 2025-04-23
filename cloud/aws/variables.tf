###############################################################################
# General
###############################################################################
variable "project_name" {
  description = "Short unique prefix for all resources (e.g. demoapp)"
  type        = string
}

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

###############################################################################
# Compute & DB
###############################################################################
variable "instance_type" {
  description = "EC2 instance size"
  type        = string
  default     = "t3.micro"
}

variable "db_engine" {
  description = "RDS engine (mysql or postgres)"
  type        = string
  default     = "mysql"
  validation {
    condition     = contains(["mysql", "postgres"], var.db_engine)
    error_message = "db_engine must be 'mysql' or 'postgres'"
  }
}

variable "db_password" {
  description = "Master password for RDS"
  type        = string
  sensitive   = true
}
