#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════
# Bootstrap Secrets Manager secrets used by the ECS task definition.
#
# Safe to commit: contains NO secret values. The DB password is read at run
# time from the local, gitignored terraform.tfvars.
#
# Run BEFORE `terraform plan`, because ecs.tf reads these secrets at plan time.
# ═══════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────
# ⚠️ REPLACE FOR A DIFFERENT APP — everything in this block is app-specific
# ───────────────────────────────────────────────────────────────────
# Must match variables.tf / terraform.tfvars:
PROJECT="${PROJECT:-app-infra}"
ENVIRONMENT="${ENVIRONMENT:-staging}"

DB_NAME="${DB_NAME:-tradescheduler}"    # REPLACE: var.db_name
DB_USER="${DB_USER:-tsadmin}"           # REPLACE: var.db_username
DB_PORT="${DB_PORT:-5432}"              # REPLACE: var.db_port
DB_ENGINE="${DB_ENGINE:-postgresql}"    # REPLACE: connection-string scheme

# REPLACE: secret names — must match var.secret_db_url_name / var.secret_key_name
SECRET_DB_URL_NAME="${SECRET_DB_URL_NAME:-db-url}"
SECRET_KEY_NAME="${SECRET_KEY_NAME:-secret-key}"

# REPLACE: this generates a Flask-style signing key. If your app has no signing
# key, delete this and the second `aws secretsmanager create-secret` below,
# and remove the matching entry from ecs.tf `secrets` + variables.tf.
SECRET_KEY_BYTES="${SECRET_KEY_BYTES:-32}"
# ───────────────────────────────────────────────────────────────────

AWS_REGION="${AWS_REGION:-eu-central-1}"
DB_INSTANCE="${DB_INSTANCE:-${PROJECT}-${ENVIRONMENT}-db}"
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

# 64 hex chars by default (Flask SECRET_KEY convention).
SECRET_KEY="$(python3 -c "import secrets; print(secrets.token_hex(${SECRET_KEY_BYTES}))")"

# Plain scheme:// URL on purpose: TradeScheduler's db_url.resolve_url() rewrites
# it to postgresql+psycopg2:// at startup. REPLACE this string format if your
# app expects a different DATABASE_URL shape.
aws secretsmanager create-secret \
  --name "${PROJECT}/${ENVIRONMENT}/${SECRET_DB_URL_NAME}" \
  --secret-string "${DB_ENGINE}://${DB_USER}:${DB_PASS}@${ENDPOINT}:${DB_PORT}/${DB_NAME}" \
  --region "$AWS_REGION" \
  --query 'ARN' --output text

aws secretsmanager create-secret \
  --name "${PROJECT}/${ENVIRONMENT}/${SECRET_KEY_NAME}" \
  --secret-string "$SECRET_KEY" \
  --region "$AWS_REGION" \
  --query 'ARN' --output text
