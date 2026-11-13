variable "region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-central-1"
}

variable "state_bucket_name" {
  description = "Globally unique S3 bucket name for Terraform state"
  type        = string
  default     = "app-infra-tfstate-970785194112"
}

