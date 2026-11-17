#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════
# Build the application image and push it to ECR.
# Pattern: build locally -> authenticate -> tag -> push.
# Run AFTER the ECR repository exists.
# ═══════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────
# ⚠️ REPLACE FOR A DIFFERENT APP — everything in this block is app-specific
# ───────────────────────────────────────────────────────────────────
APP_DIR="${APP_DIR:-../scheduler-app}"  # REPLACE: path to your app source
REPO="${REPO:-tradescheduler}"          # REPLACE: var.app_name / ECR repo name
IMAGE_TAG="${IMAGE_TAG:-latest}"        # REPLACE: prefer a commit SHA in prod
# ‼️ The app's Dockerfile must EXPOSE the same port as var.app_port.
# ‼️ Its health endpoint must return var.health_check_matcher on
#    var.health_check_path, otherwise the ALB never marks tasks healthy.
# ───────────────────────────────────────────────────────────────────

AWS_REGION="${AWS_REGION:-eu-central-1}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"

REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
ECR_URI="${REGISTRY}/${REPO}"

cd "$APP_DIR"

echo "==> docker build"
docker build -t "${REPO}:${IMAGE_TAG}" .

echo "==> ECR login (password piped via stdin, never printed)"
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

echo "==> tag + push"
docker tag "${REPO}:${IMAGE_TAG}" "${ECR_URI}:${IMAGE_TAG}"
docker push "${ECR_URI}:${IMAGE_TAG}"

echo "==> pushed: ${ECR_URI}:${IMAGE_TAG}"
