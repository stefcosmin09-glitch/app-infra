# ── RDS PostgreSQL ─────────────────────────────────────
# TradeScheduler needs a relational DB. We use PostgreSQL (matches the app's
# production stack). Single-AZ for cost control; README explains why Multi-AZ
# in prod.

# Subnet group: RDS requires at least 2 AZs in the group, even for Single-AZ.
# This allows future Multi-AZ upgrade without recreating the instance.
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-${var.environment}-db-subnet-group"
  subnet_ids = module.vpc.private_subnet_ids

  tags = {
    Name        = "${var.project_name}-${var.environment}-db-subnet-group"
    Project     = var.project_name
    Environment = var.environment
  }
}

# RDS instance: PostgreSQL on db.t3.micro (free-tier eligible).
resource "aws_db_instance" "main" {
  identifier = "${var.project_name}-${var.environment}-db"

  # Engine: PostgreSQL (app uses PostgreSQL in production).
  # Pin only the MAJOR version: with auto_minor_version_upgrade = true (the
  # default), the AWS provider resolves "16" to the newest available minor
  # (e.g. 16.15). Hardcoding "16.9" broke after AWS retired that minor version.
  engine                     = "postgres"
  engine_version             = "16"
  auto_minor_version_upgrade = true

  # Sizing: smallest instance + 20 GB gp3 storage
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp3"

  # ⚠️ APP-SPECIFIC credentials: db_name / db_username / db_password
  # come from terraform.tfvars (password is never committed).
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  # Networking: private subnets only, SG restricts access to ECS
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  # Backup: 1 day — free-tier accounts reject longer retention
  # (FreeTierRestrictionError). Use 7+ days in production.
  backup_retention_period = 1

  # Demo-only: skip final snapshot so terraform destroy is fast.
  # In production, set skip_final_snapshot = false and provide final_snapshot_identifier.
  skip_final_snapshot = true

  # Deletion protection off for demo; enable in prod.
  deletion_protection = false

  tags = {
    Name        = "${var.project_name}-${var.environment}-db"
    Project     = var.project_name
    Environment = var.environment
  }
}
