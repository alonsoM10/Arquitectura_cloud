#!/usr/bin/env bash
# =====================================================================
#  EP2 — DEPLOY LOCAL (Git Bash / VS Code)
#  Replica el workflow deploy-ep2.yml paso a paso. Idempotente:
#  si algo falla, lo arreglas y vuelves a correrlo (el tfstate es local).
#
#  REQUISITOS (en esta misma terminal):
#   · Credenciales del Learner Lab cargadas (aws sts debe responder)
#   · Docker Desktop ENCENDIDO (para compilar ARM64)
#   · terraform, kubectl, helm, jq, docker en el PATH
#
#  USO:  bash infra/scripts-ep2/deploy-local.sh
# =====================================================================
set -euo pipefail

AWS_REGION=us-east-1
CLUSTER_NAME=freshbox-cluster
NAMESPACE=freshbox
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TF_DIR="$ROOT/infra/terraform-ep2"

echo "############ 0/9  Chequeo de requisitos ############"
command -v terraform >/dev/null || { echo "FALTA terraform"; exit 1; }
command -v kubectl   >/dev/null || { echo "FALTA kubectl";   exit 1; }
command -v helm      >/dev/null || { echo "FALTA helm";       exit 1; }
command -v jq        >/dev/null || { echo "FALTA jq";         exit 1; }
command -v docker    >/dev/null || { echo "FALTA docker";     exit 1; }
docker info >/dev/null 2>&1      || { echo "Docker Desktop NO esta corriendo"; exit 1; }
aws sts get-caller-identity --output text >/dev/null || { echo "Sin credenciales AWS"; exit 1; }
echo "   -> OK"

echo "############ 1/9  Terraform: infra (VPC+NAT+SG+KMS+RDS+ECR+EKS) ############"
cd "$TF_DIR"
terraform init -input=false
terraform apply -auto-approve -input=false

ACCOUNT_ID="$(terraform output -raw account_id)"
RDS_ENDPOINT="$(terraform output -raw rds_endpoint)"
DB_NAME="$(terraform output -raw db_name)"
DB_SECRET_ARN="$(terraform output -raw db_secret_arn)"
VPC_ID="$(terraform output -raw vpc_id)"
ALB_SG_ID="$(terraform output -raw alb_security_group_id)"
PUBLIC_SUBNET_IDS="$(terraform output -json public_subnet_ids | jq -r 'join(",")')"
cd "$ROOT"

echo "############ 2/9  Build + push de las 5 imagenes ARM64 a ECR ############"
AWS_REGION="$AWS_REGION" TARGET_PLATFORM="linux/arm64" bash infra/scripts-ep2/ecr-push.sh

echo "############ 3/9  kubectl: acceso al cluster ############"
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"
kubectl get nodes -o wide
echo "   esperando nodos Ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=10m

echo "############ 4/9  metrics-server (para el HPA) ############"
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.7.2/components.yaml
kubectl -n kube-system rollout status deployment/metrics-server --timeout=5m

echo "############ 5/9  AWS Load Balancer Controller (Helm) ############"
helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
helm repo update
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set region="$AWS_REGION" \
  --set vpcId="$VPC_ID" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set enableShield=false --set enableWaf=false --set enableWafv2=false \
  --wait --timeout 10m
kubectl -n kube-system rollout status deployment/aws-load-balancer-controller --timeout=5m

echo "############ 6/9  Namespace + ConfigMap + Secret (desde Secrets Manager) ############"
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

echo "############ 7/9  Seed de la RDS (Job efimero) ############"
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

echo "############ 8/9  Deployments + Services + Ingress + HPA ############"
for f in k8s/*-deployment.yaml; do
  sed "s|<ACCOUNT_ID>|${ACCOUNT_ID}|g" "$f" | kubectl apply -f -
done
sed -e "s|\${PUBLIC_SUBNET_IDS}|${PUBLIC_SUBNET_IDS}|g" \
    -e "s|\${ALB_SG_ID}|${ALB_SG_ID}|g" k8s/ingress.yaml | kubectl apply -f -
kubectl apply -f k8s/hpa.yaml

echo "   esperando a que los 10 pods esten Running..."
for d in frontend get-products create-product update-product delete-product; do
  kubectl -n "$NAMESPACE" rollout status deploy/"$d" --timeout=5m
done

echo "############ 8.5  CloudWatch Container Insights (best-effort) ############"
aws eks create-addon --cluster-name "$CLUSTER_NAME" \
  --addon-name amazon-cloudwatch-observability --region "$AWS_REGION" \
  || echo "   Container Insights no disponible en el lab (documentar en el informe)."

echo "############ 9/9  Esperando URL del ALB ############"
ALB_URL=""
for i in $(seq 1 40); do
  HOST="$(kubectl -n "$NAMESPACE" get ingress freshbox-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  if [ -n "$HOST" ]; then ALB_URL="http://$HOST"; break; fi
  echo "   esperando al ALB ($i/40)..."; sleep 15
done

echo ""
echo "########################################################"
if [ -n "$ALB_URL" ]; then
  echo "  DEPLOY OK. URL de la app:  $ALB_URL"
  echo "  Prueba:  curl $ALB_URL/api/products"
else
  echo "  Pods arriba pero el ALB aun no da URL. Revisa:"
  echo "  kubectl -n kube-system logs deploy/aws-load-balancer-controller --tail=50"
fi
echo "  RDS (Multi-AZ):  $RDS_ENDPOINT"
echo "########################################################"
