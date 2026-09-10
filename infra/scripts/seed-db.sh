#!/usr/bin/env bash
# Siembra la BD RDS ejecutando una tarea Fargate efimera (mysql) DENTRO de
# la VPC. No requiere abrir la RDS a Internet ni instalar el cliente mysql.
# Requisitos: credenciales del lab activas y que exista la task 'freshbox-seed'
# (creada por 'terraform apply').
set -euo pipefail

cd "$(dirname "$0")/../terraform"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
PREFIX="${NAME_PREFIX:-freshbox}"

CLUSTER="$(terraform output -raw cluster_name)"
SG="$(terraform output -raw app_sg_id)"
SUBNETS="$(terraform output -json public_subnet_ids | tr -d '[]" \n\r\t ')"

echo ">> Lanzando tarea de seed en $CLUSTER ..."
TASK_ARN="$(aws ecs run-task \
  --cluster "$CLUSTER" \
  --task-definition "${PREFIX}-seed" \
  --launch-type FARGATE \
  --region "$REGION" \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SG],assignPublicIp=ENABLED}" \
  --query 'tasks[0].taskArn' --output text)"

echo ">> Tarea: $TASK_ARN"
echo ">> Esperando a que termine (puede tomar ~1-2 min)..."
aws ecs wait tasks-stopped --cluster "$CLUSTER" --tasks "$TASK_ARN" --region "$REGION"

CODE="$(aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$TASK_ARN" \
  --region "$REGION" --query 'tasks[0].containers[0].exitCode' --output text)"

echo ">> Logs de la tarea:"
aws logs tail "/ecs/${PREFIX}/seed" --region "$REGION" --since 5m 2>/dev/null || true

echo ">> Exit code = $CODE"
if [ "$CODE" = "0" ]; then
  echo ">> OK. BD sembrada. Pulsa 'Cargar productos' en la web."
else
  echo ">> Algo fallo. Revisa los logs de arriba."
fi
