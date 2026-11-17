#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Build the real TradeScheduler image and push it to ECR.
#
# Pattern: build locally -> authenticate -> tag -> push.
# Run AFTER the ECR repository exists (terraform apply -target=... or full apply).
# ─────────────────────────────────────────────────────────────────────────────

AWS_REGION="${AWS_REGION:-eu-central-1}"
REPO="${REPO:-tradescheduler}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
APP_DIR="${APP_DIR:-../scheduler-app}"

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
