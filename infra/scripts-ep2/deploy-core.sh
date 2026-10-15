#!/usr/bin/env bash
# =====================================================================
#  EP2 — FASE 1: NUCLEO (lo robusto, sin el ALB publico)
#  Deja: cluster EKS + 2 nodos Ready + RDS Multi-AZ + 5 imagenes en ECR
#        + 10 pods Running + HPA con metricas + seed de la BD.
#  NO instala el ALB Controller (eso es la fase 2, lo unico fragil).
#  Idempotente: si falla, arreglas y vuelves a correrlo.
#
#  REQUISITOS: credenciales del lab cargadas, Docker Desktop ENCENDIDO,
#              terraform/kubectl/jq/docker en el PATH.
#  USO:  bash infra/scripts-ep2/deploy-core.sh
# =====================================================================
set -euo pipefail

AWS_REGION=us-east-1
CLUSTER_NAME=freshbox-cluster
NAMESPACE=freshbox
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TF_DIR="$ROOT/infra/terraform-ep2"

echo "############ 0/8  Chequeo de requisitos ############"
for c in terraform kubectl jq docker; do command -v "$c" >/dev/null || { echo "FALTA $c"; exit 1; }; done
docker info >/dev/null 2>&1 || { echo "Docker Desktop NO esta corriendo"; exit 1; }
aws sts get-caller-identity --output text >/dev/null || { echo "Sin credenciales AWS"; exit 1; }
echo "   -> OK"

echo "############ 1/8  Terraform: infra (VPC+NAT+SG+KMS+RDS+ECR+EKS) ############"
cd "$TF_DIR"
terraform init -input=false
terraform apply -auto-approve -input=false
ACCOUNT_ID="$(terraform output -raw account_id)"
RDS_ENDPOINT="$(terraform output -raw rds_endpoint)"
DB_NAME="$(terraform output -raw db_name)"
DB_SECRET_ARN="$(terraform output -raw db_secret_arn)"
cd "$ROOT"

echo "############ 2/8  Build + push de las 5 imagenes ARM64 a ECR ############"
AWS_REGION="$AWS_REGION" TARGET_PLATFORM="linux/arm64" bash infra/scripts-ep2/ecr-push.sh

echo "############ 3/8  kubectl: acceso al cluster + nodos Ready ############"
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"
kubectl get nodes -o wide
kubectl wait --for=condition=Ready nodes --all --timeout=10m

echo "############ 4/8  metrics-server (para el HPA) ############"
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.7.2/components.yaml
kubectl -n kube-system rollout status deployment/metrics-server --timeout=5m

echo "############ 5/8  Namespace + ConfigMap + Secret (desde Secrets Manager) ############"
kubectl apply -f k8s/namespace.yaml
SECRET_JSON="$(aws secretsmanager get-secret-value --secret-id "$DB_SECRET_ARN" --query SecretString --output text)"
DB_USER="$(echo "$SECRET_JSON" | jq -r .username)"
DB_PASS="$(echo "$SECRET_JSON" | jq -r .password)"
kubectl create configmap freshbox-config -n "$NAMESPACE" \
  --from-literal=DB_HOST="$RDS_ENDPOINT" --from-literal=DB_NAME="$DB_NAME" --from-literal=DB_PORT="3306" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic freshbox-secret -n "$NAMESPACE" \
  --from-literal=DB_USER="$DB_USER" --from-literal=DB_PASS="$DB_PASS" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "############ 6/8  Seed de la RDS (Job efimero) ############"
kubectl create configmap freshbox-initsql -n "$NAMESPACE" \
  --from-file=init.sql=app-ep2/init.sql --dry-run=client -o yaml | kubectl apply -f -
kubectl delete job freshbox-seed -n "$NAMESPACE" --ignore-not-found
cat <<'EOF' | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata: { name: freshbox-seed, namespace: freshbox }
spec:
  backoffLimit: 3
  template:
    spec:
      restartPolicy: OnFailure
      containers:
        - name: seed
          image: mysql:8.0
          command: ["/bin/sh","-c"]
          args:
            - mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < /sql/init.sql && echo "SEED OK"
          envFrom:
            - configMapRef: { name: freshbox-config }
            - secretRef:    { name: freshbox-secret }
          volumeMounts:
            - { name: sql, mountPath: /sql }
      volumes:
        - name: sql
          configMap: { name: freshbox-initsql }
EOF
kubectl wait --for=condition=complete job/freshbox-seed -n "$NAMESPACE" --timeout=5m
kubectl logs job/freshbox-seed -n "$NAMESPACE"

echo "############ 7/8  Deployments + Services + HPA (SIN ingress) ############"
for f in k8s/*-deployment.yaml; do
  sed "s|<ACCOUNT_ID>|${ACCOUNT_ID}|g" "$f" | kubectl apply -f -
done
kubectl apply -f k8s/hpa.yaml
for d in frontend get-products create-product update-product delete-product; do
  kubectl -n "$NAMESPACE" rollout status deploy/"$d" --timeout=5m
done

echo "############ 8/8  CloudWatch Container Insights (best-effort) ############"
aws eks create-addon --cluster-name "$CLUSTER_NAME" \
  --addon-name amazon-cloudwatch-observability --region "$AWS_REGION" \
  || echo "   Container Insights no disponible en el lab (documentar en el informe)."

echo ""
echo "########################################################"
echo "  FASE 1 (NUCLEO) LISTA."
kubectl -n "$NAMESPACE" get pods -o wide
echo "  --------------------------------------------------"
kubectl -n "$NAMESPACE" get hpa
echo "  RDS (Multi-AZ):  $RDS_ENDPOINT"
echo "  Siguiente:  bash infra/scripts-ep2/deploy-alb.sh   (expone el CRUD publico)"
echo "  Plan B CRUD sin ALB:  kubectl -n freshbox port-forward svc/get-products 3001:3001"
echo "########################################################"
