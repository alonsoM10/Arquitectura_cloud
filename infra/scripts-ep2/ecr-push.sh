#!/usr/bin/env bash
# =====================================================================
#  EP2 — Build + push de las 5 imágenes a ECR, compiladas para ARM64.
#
#  DIFERENCIA CRÍTICA CON EP1: el Node Group usa t4g.small, que son
#  instancias Graviton (ARM64). Las imágenes de EP1 estaban compiladas
#  para linux/amd64 porque Fargate corría en X86_64. Si se reutilizan,
#  los Pods quedan en CrashLoopBackOff con "exec format error".
#
#  Uso:  bash infra/scripts-ep2/ecr-push.sh
# =====================================================================
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
PREFIX="${NAME_PREFIX:-freshbox}"
PLATFORM="${TARGET_PLATFORM:-linux/arm64}"

BACKENDS=(get-products create-product update-product delete-product)

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

echo ">> Plataforma de compilacion: ${PLATFORM}"
echo ">> Login a ECR (${REGISTRY})"
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

build_and_push() {
  local name="$1" context="$2"
  local image="${REGISTRY}/${PREFIX}-${name}:latest"

  echo ">> Build ${name} (${PLATFORM})"
  docker buildx build \
    --platform "$PLATFORM" \
    --tag "$image" \
    --push \
    "$context"

  echo ">> Publicada ${image}"
}

# --- Frontend Nginx ---
build_and_push "frontend" "${ROOT}/app-ep2/frontend"

# --- 4 microservicios Node.js ---
for svc in "${BACKENDS[@]}"; do
  build_and_push "$svc" "${ROOT}/app-ep2/backend/${svc}"
done

echo ">> Listo. Las 5 imagenes ARM64 estan en ECR."
