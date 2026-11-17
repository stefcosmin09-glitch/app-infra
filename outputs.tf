# ── Useful outputs ───────────────────────────────────────
# Outputs are printed after `terraform apply` and can be queried any time
# with `terraform output`. They are the "public interface" of this stack.

# Public entry point for the app.
# Test with: curl http://$(terraform output -raw alb_dns_name)/health
output "alb_dns_name" {
  description = "Public DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

# Registry URI used by `docker push` when releasing a new image.
output "ecr_repository_url" {
  description = "ECR repository URI (append :TAG when pushing)"
  value       = aws_ecr_repository.app.repository_url
}

# Cluster/service names — handy for `aws ecs ...` debugging commands.
output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.app.name
}

# RDS endpoint is needed when creating/updating the DATABASE_URL secret.
output "db_endpoint" {
  description = "RDS PostgreSQL endpoint (host only, no port)"
  value       = aws_db_instance.main.address
}
