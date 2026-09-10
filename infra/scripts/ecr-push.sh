#!/usr/bin/env bash
# Build + push de las 4 imagenes backend a ECR (plataforma linux/amd64).
# Requiere: Docker Desktop corriendo y credenciales del Learner Lab activas.
# Uso:  bash infra/scripts/ecr-push.sh
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
PREFIX="${NAME_PREFIX:-freshbox}"
SERVICES=(get-products create-product update-product delete-product)

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
APP_DIR="$(cd "$(dirname "$0")/../../app/microserviciosBackend" && pwd)"

echo ">> Login a ECR (${REGISTRY})"
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

for svc in "${SERVICES[@]}"; do
  IMAGE="${REGISTRY}/${PREFIX}-${svc}:latest"
  echo ">> Build ${svc}"
  docker build --platform linux/amd64 -t "$IMAGE" "${APP_DIR}/${svc}"
  echo ">> Push ${svc}"
  docker push "$IMAGE"
done

echo ">> Forzando nuevo despliegue en ECS"
for svc in "${SERVICES[@]}"; do
  aws ecs update-service --cluster "${PREFIX}-cluster" \
    --service "${PREFIX}-${svc}" --force-new-deployment --region "$REGION" >/dev/null || true
done

echo ">> Listo. Las 4 imagenes estan en ECR y ECS redesplegara las tareas."
