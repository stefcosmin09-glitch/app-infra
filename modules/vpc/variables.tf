variable "project_name" {
  description = "Project name for tagging"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/20"
}

variable "azs" {
  description = "Availability zones to use"
  type        = list(string)
  default     = ["eu-central-1a", "eu-central-1b"]
}