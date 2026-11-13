# Remote state: S3 bucket + DynamoDB lock table (created by bootstrap/).
# Do NOT commit terraform.tfstate — it lives in S3.

terraform {
  backend "s3" {
    bucket       = "app-infra-tfstate-970785194112"
    key          = "app-infra/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}