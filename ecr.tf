# ── ECR Repository ─────────────────────────────────────
# ⚠️ APP-SPECIFIC: repository name comes from var.app_name (terraform.tfvars).
resource "aws_ecr_repository" "app" {
  name                 = var.app_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  # DEMO ONLY: let `terraform destroy` remove the repo even if images remain.
  # AWS otherwise refuses with RepositoryNotEmptyException. In production keep
  # this false and prune images explicitly (lifecycle policy) instead.
  force_delete = true

  tags = {
    Name        = var.app_name
    Project     = var.project_name
    Environment = var.environment
  }
}
