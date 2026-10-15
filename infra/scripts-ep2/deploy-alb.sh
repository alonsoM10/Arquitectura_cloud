#!/usr/bin/env bash
# =====================================================================
#  EP2 — FASE 2: ALB PUBLICO (lo unico fragil: sin IRSA/OIDC en el lab)
#  Instala el AWS Load Balancer Controller, aplica el Ingress y valida
#  el CRUD end-to-end por el DNS publico del ALB.
#  Correr DESPUES de que la fase 1 (deploy-core.sh) haya quedado OK.
#  Si esto falla por el lab, el CRUD se demuestra con port-forward
#  (ver el final) y se justifica en el informe.
#
#  USO:  bash infra/scripts-ep2/deploy-alb.sh
# =====================================================================
set -euo pipefail

AWS_REGION=us-east-1
CLUSTER_NAME=freshbox-cluster
NAMESPACE=freshbox
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TF_DIR="$ROOT/infra/terraform-ep2"

echo "############ 1/4  Leyendo salidas de Terraform ############"
cd "$TF_DIR"
VPC_ID="$(terraform output -raw vpc_id)"
ALB_SG_ID="$(terraform output -raw alb_security_group_id)"
PUBLIC_SUBNET_IDS="$(terraform output -json public_subnet_ids | jq -r 'join(",")')"
cd "$ROOT"
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null

echo "############ 2/4  AWS Load Balancer Controller (Helm) ############"
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

echo "############ 3/4  Aplicando el Ingress ############"
sed -e "s|\${PUBLIC_SUBNET_IDS}|${PUBLIC_SUBNET_IDS}|g" \
    -e "s|\${ALB_SG_ID}|${ALB_SG_ID}|g" k8s/ingress.yaml | kubectl apply -f -

echo "############ 4/4  Esperando la URL del ALB ############"
ALB_URL=""
for i in $(seq 1 40); do
  HOST="$(kubectl -n "$NAMESPACE" get ingress freshbox-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  if [ -n "$HOST" ]; then ALB_URL="http://$HOST"; break; fi
  echo "   esperando al ALB ($i/40)..."; sleep 15
done

if [ -z "$ALB_URL" ]; then
  echo ""
  echo "########################################################"
  echo "  El ALB no dio URL. Revisa el controller:"
  echo "  kubectl -n kube-system logs deploy/aws-load-balancer-controller --tail=60"
  echo "  PLAN B (demostrar CRUD sin ALB):"
  echo "  kubectl -n freshbox port-forward svc/get-products 3001:3001"
  echo "  luego:  curl http://localhost:3001/api/products"
  echo "########################################################"
  exit 1
fi

echo ">> ALB listo: $ALB_URL  — esperando a que responda..."
for i in $(seq 1 30); do curl -fsS "$ALB_URL/api/products" >/dev/null 2>&1 && break; sleep 10; done

echo ">> GET (catalogo inicial)";  curl -fsS "$ALB_URL/api/products" | head -c 400; echo
echo ">> POST (crear)"
NEW_ID="$(curl -fsS -X POST "$ALB_URL/api/products" -H 'Content-Type: application/json' \
  -d '{"nombre":"Prueba CRUD","descripcion":"alta","precio":1990,"stock":7,"categoria":"Frutas"}' | jq -r '.id // empty')"
echo "   id creado: ${NEW_ID:-<sin id>}"
if [ -n "${NEW_ID:-}" ]; then
  echo ">> PUT (modificar)"
  curl -fsS -X PUT "$ALB_URL/api/products/$NEW_ID" -H 'Content-Type: application/json' \
    -d '{"nombre":"Prueba CRUD editada","descripcion":"mod","precio":2990,"stock":3,"categoria":"Frutas"}' | head -c 300; echo
  echo ">> DELETE (eliminar)"; curl -fsS -X DELETE "$ALB_URL/api/products/$NEW_ID" | head -c 300; echo
fi
echo ">> GET (catalogo final)"; curl -fsS "$ALB_URL/api/products" | head -c 400; echo

echo ""
echo "########################################################"
echo "  FASE 2 OK — CRUD validado por el ALB publico."
echo "  URL de la app:  $ALB_URL"
echo "########################################################"
