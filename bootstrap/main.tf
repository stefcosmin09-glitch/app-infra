# Bootstrap: creates the S3 bucket + DynamoDB table used as Terraform backend.
# This directory uses LOCAL state (no backend block) because the backend
# does not exist yet — chicken-and-egg problem.
# Run once: cd bootstrap && terraform init && terraform apply

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# ── S3 bucket for Terraform state ──────────────────────

resource "aws_s3_bucket" "tf_state" {
  bucket = var.state_bucket_name

  tags = {
    Name      = "Terraform State"
    Project   = "app-infra"
    ManagedBy = "terraform"
  }
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# State locking is handled natively by S3 (use_lockfile = true in backend.tf).
# DynamoDB table is no longer needed (Terraform >= 1.10).