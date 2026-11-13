variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Project name used for tagging and naming"
  type        = string
  default     = "app-infra"
}

variable "environment" {
  description = "Environment name (staging, prod)"
  type        = string
  default     = "staging"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/20"
}

variable "app_port" {
  description = "Port the container listens on (Dockerfile EXPOSE)"
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "Health check endpoint path"
  type        = string
  default     = "/health"
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "tradescheduler"
}

variable "db_username" {
  description = "PostgreSQL master username"
  type        = string
  default     = "tsadmin"
  sensitive   = true
}

variable "db_password" {
  description = "PostgreSQL master password (set via tfvars or env, never commit)"
  type        = string
  sensitive   = true
}

variable "container_image" {
  description = "Docker image URI in ECR (set after first build/push)"
  type        = string
  default     = ""
}