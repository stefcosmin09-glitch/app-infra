# ═══════════════════════════════════════════════════════════════════
# GENERIC SETTINGS — normally unchanged when swapping applications
# ═══════════════════════════════════════════════════════════════════

variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Project name used for tagging and naming AWS resources"
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

variable "container_image" {
  description = "Explicit Docker image URI. Leave empty to use the ECR repo created here + :latest"
  type        = string
  default     = ""
}

# Fargate sizing — generic tuning knobs (safe to override per environment).
variable "task_cpu" {
  description = "Fargate CPU units (256 = 0.25 vCPU)"
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Fargate memory in MB (512 = 0.5 GB)"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Number of ECS tasks to keep running"
  type        = number
  default     = 1
}

# ═══════════════════════════════════════════════════════════════════
# ⚠️ APP-SPECIFIC — REPLACE THESE VALUES FOR A DIFFERENT APPLICATION
# Everything below describes TradeScheduler. Override in terraform.tfvars.
# See README → "Adapting this stack for a different application".
# ═══════════════════════════════════════════════════════════════════

variable "app_name" {
  description = "REPLACE: ECR repository name AND ECS container name"
  type        = string
  default     = "tradescheduler"
}

variable "app_port" {
  description = "REPLACE: port the container listens on (must match Dockerfile EXPOSE)"
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "REPLACE: HTTP path the ALB health check calls (must return 200 when healthy)"
  type        = string
  default     = "/health"
}

variable "health_check_matcher" {
  description = "REPLACE: HTTP status code considered healthy"
  type        = string
  default     = "200"
}

variable "db_name" {
  description = "REPLACE: PostgreSQL database name created by RDS"
  type        = string
  default     = "tradescheduler"
}

variable "db_username" {
  description = "REPLACE: PostgreSQL master username"
  type        = string
  default     = "tsadmin"
  sensitive   = true
}

variable "db_password" {
  description = "PostgreSQL master password (set via tfvars or env, never commit)"
  type        = string
  sensitive   = true
}

variable "db_port" {
  description = "REPLACE: database port (also used in the RDS security group)"
  type        = number
  default     = 5432
}

variable "secret_db_url_name" {
  description = "REPLACE: Secrets Manager secret name for the DB connection string"
  type        = string
  default     = "db-url"
}

variable "secret_key_name" {
  description = "REPLACE: Secrets Manager secret name for the app signing key (remove if not needed)"
  type        = string
  default     = "secret-key"
}

variable "env_database_url" {
  description = "REPLACE: env var name the app reads the DB URL from"
  type        = string
  default     = "DATABASE_URL"
}

variable "env_secret_key" {
  description = "REPLACE: env var name the app reads its signing key from (remove if not needed)"
  type        = string
  default     = "SECRET_KEY"
}

variable "app_environment" {
  description = "REPLACE: plain (non-secret) environment variables injected into the container"
  type        = map(string)
  default = {
    FLASK_ENV = "production"
  }
}
