#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Bootstrap Secrets Manager secrets used by the ECS task definition.
#
# Safe to commit: contains NO secret values. The DB password is read at run
# time from the local, gitignored terraform.tfvars.
#
# Run BEFORE `terraform plan`, because the ecs.tf data sources look these
# secrets up at plan time and fail fast if they are missing.
# ─────────────────────────────────────────────────────────────────────────────

PROJECT="${PROJECT:-app-infra}"
ENVIRONMENT="${ENVIRONMENT:-staging}"
AWS_REGION="${AWS_REGION:-eu-central-1}"
DB_INSTANCE="${DB_INSTANCE:-${PROJECT}-${ENVIRONMENT}-db}"
DB_NAME="${DB_NAME:-tradescheduler}"
DB_USER="${DB_USER:-tsadmin}"
TFVARS="${TFVARS:-terraform.tfvars}"

# Read password from tfvars. Greedy match to the last quote so passwords with
# special characters still work. Never echo it.
DB_PASS="$(sed -nE 's/^[[:space:]]*db_password[[:space:]]*=[[:space:]]*"(.*)"[[:space:]]*$/\1/p' "$TFVARS" | head -n 1)"
if [ -z "$DB_PASS" ]; then
  echo "ERROR: db_password not found in $TFVARS" >&2
  exit 1
fi

ENDPOINT="$(aws rds describe-db-instances \
  --db-instance-identifier "$DB_INSTANCE" \
  --query 'DBInstances[0].Endpoint.Address' --output text \
  --region "$AWS_REGION")"

# 64 hex chars, same as the app's own documentation for SECRET_KEY.
SECRET_KEY="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"

# Plain postgresql:// URL on purpose: the app's db_url.resolve_url() rewrites
# it to postgresql+psycopg2:// at startup. Do NOT add the driver here.
aws secretsmanager create-secret \
  --name "${PROJECT}/${ENVIRONMENT}/db-url" \
  --secret-string "postgresql://${DB_USER}:${DB_PASS}@${ENDPOINT}:5432/${DB_NAME}" \
  --region "$AWS_REGION" \
  --query 'ARN' --output text

aws secretsmanager create-secret \
  --name "${PROJECT}/${ENVIRONMENT}/secret-key" \
  --secret-string "$SECRET_KEY" \
  --region "$AWS_REGION" \
  --query 'ARN' --output text
