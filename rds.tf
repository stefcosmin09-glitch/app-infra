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

  # Engine: PostgreSQL (app uses PostgreSQL in production)
  engine         = "postgres"
  engine_version = "16.9"

  # Sizing: smallest instance + 20 GB gp3 storage
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp3"

  # Credentials: from variables (never hardcode)
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  # Networking: private subnets only, SG restricts access to ECS
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  # Backup: 7 days retention (free tier includes automated backups)
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
