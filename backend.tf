# Remote state: S3 bucket created by bootstrap/.
# Locking is native S3 (use_lockfile = true) — no DynamoDB table.
# Do NOT commit terraform.tfstate — it lives in S3.
#
# ⚠️ REPLACE: bucket / key / region must match your own bootstrap/ before
# reusing this template in another account (Terraform forbids variables here).

terraform {
  backend "s3" {
    bucket       = "app-infra-tfstate-970785194112"
    key          = "app-infra/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}