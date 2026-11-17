# ── ECS Fargate ────────────────────────────────────────

# CloudWatch log group for container logs
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project_name}-${var.environment}"
  retention_in_days = 14

  tags = {
    Name        = "${var.project_name}-${var.environment}-logs"
    Project     = var.project_name
    Environment = var.environment
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-${var.environment}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-cluster"
    Project     = var.project_name
    Environment = var.environment
  }
}

# ── Secrets Manager lookups ─────────────────────────────
# We look secrets up BY NAME, never by a hand-built ARN.
#
# WHY: AWS appends a random 6-character suffix to every secret ARN.
#   name: "app-infra/staging/db-url"
#   real ARN: "...:secret:app-infra/staging/db-url-A1b2C3"
# If we build the ARN ourselves (as before), it is missing that suffix,
# ECS cannot find the secret, and the task fails at startup.
# A data source asks AWS for the real, complete ARN instead.
#
# IMPORTANT: data sources are read at PLAN time, so these secrets must
# already exist in Secrets Manager before `terraform plan` will succeed.
data "aws_secretsmanager_secret" "db_url" {
  name = "${var.project_name}/${var.environment}/db-url"
}

data "aws_secretsmanager_secret" "secret_key" {
  name = "${var.project_name}/${var.environment}/secret-key"
}

# Task Definition: describes how to run the container
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project_name}-${var.environment}-task"
  network_mode             = "awsvpc" # required for Fargate
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256" # 0.25 vCPU
  memory                   = "512" # 0.5 GB
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = var.container_image != "" ? var.container_image : "${aws_ecr_repository.tradescheduler.repository_url}:latest"
      essential = true

      portMappings = [
        {
          containerPort = var.app_port
          hostPort      = var.app_port
          protocol      = "tcp"
        }
      ]

      # Environment variables (non-secret)
      environment = [
        { name = "FLASK_ENV", value = "production" },
        { name = "PORT", value = tostring(var.app_port) }
      ]

      # Secrets from AWS Secrets Manager (injected as env vars).
      # The ECS agent reads these ARNs at task startup, fetches the values
      # using the execution role, and injects them as environment variables.
      # We use the .arn from the data sources above (never a hardcoded ARN).
      secrets = [
        { name = "DATABASE_URL", valueFrom = data.aws_secretsmanager_secret.db_url.arn },
        { name = "SECRET_KEY", valueFrom = data.aws_secretsmanager_secret.secret_key.arn }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "app"
        }
      }
    }
  ])

  tags = {
    Name        = "${var.project_name}-${var.environment}-task"
    Project     = var.project_name
    Environment = var.environment
  }
}

# ECS Service: runs and maintains the desired number of tasks
resource "aws_ecs_service" "app" {
  name            = "${var.project_name}-${var.environment}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = module.vpc.private_subnet_ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = var.app_port
  }

  depends_on = [aws_lb_listener.http]

  tags = {
    Name        = "${var.project_name}-${var.environment}-service"
    Project     = var.project_name
    Environment = var.environment
  }
}