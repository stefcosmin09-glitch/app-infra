variable "region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-central-1"
}

variable "state_bucket_name" {
  # REPLACE: include your own AWS account ID — S3 names are globally unique.
  description = "REPLACE: globally unique S3 bucket name for Terraform state"
  type        = string
  default     = "app-infra-tfstate-970785194112"
}

