# ── ECR Repository ─────────────────────────────────────
resource "aws_ecr_repository" "tradescheduler" {
  name                 = "tradescheduler"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name        = "tradescheduler"
    Project     = var.project_name
    Environment = var.environment
  }
}