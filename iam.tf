# ── IAM Roles for ECS ──────────────────────────────────

# Trust policy: allows ECS tasks to assume these roles.
# "sts:AssumeRole" means "this service can borrow the role's permissions".
data "aws_iam_policy_document" "ecs_task_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

# ── Execution Role ──────────────────────────────────────
# Used by the ECS AGENT (not your app) to:
#   - Pull Docker image from ECR
#   - Read secrets from Secrets Manager (for env vars)
#   - Write logs to CloudWatch
resource "aws_iam_role" "ecs_execution" {
  name               = "${var.project_name}-${var.environment}-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json

  tags = {
    Name        = "${var.project_name}-${var.environment}-ecs-execution-role"
    Project     = var.project_name
    Environment = var.environment
  }
}

# Attach AWS managed policy (auto-updated by AWS when new permissions needed)
resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Inline policy: allow reading secrets from Secrets Manager
# (needed because DB password will be stored there)
resource "aws_iam_role_policy" "ecs_execution_secrets" {
  name = "${var.project_name}-${var.environment}-ecs-secrets"
  role = aws_iam_role.ecs_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = "*" # In prod, restrict to specific secret ARN
      }
    ]
  })
}

# ── Task Role ───────────────────────────────────────────
# Used by YOUR APP (container) to access AWS services from code.
# TradeScheduler doesn't use AWS services directly (no S3, SQS, etc.),
# so this role is minimal. Add permissions here if the app needs them.
resource "aws_iam_role" "ecs_task" {
  name               = "${var.project_name}-${var.environment}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json

  tags = {
    Name        = "${var.project_name}-${var.environment}-ecs-task-role"
    Project     = var.project_name
    Environment = var.environment
  }
}