#!/usr/bin/env bash
VPC=vpc-0244430b770aff030
REGION=us-east-1

echo "## 1) Quitando reglas de los SGs (rompe las referencias cruzadas)"
for sg in $(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC" \
            --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text --region $REGION); do
  ing=$(aws ec2 describe-security-groups --group-ids "$sg" --region $REGION \
        --query 'SecurityGroups[0].IpPermissions' --output json)
  if [ "$ing" != "[]" ] && [ -n "$ing" ]; then
    aws ec2 revoke-security-group-ingress --group-id "$sg" --ip-permissions "$ing" --region $REGION >/dev/null 2>&1 \
      && echo "   -> ingress de $sg revocado"
  fi
  eg=$(aws ec2 describe-security-groups --group-ids "$sg" --region $REGION \
       --query 'SecurityGroups[0].IpPermissionsEgress' --output json)
  if [ "$eg" != "[]" ] && [ -n "$eg" ]; then
    aws ec2 revoke-security-group-egress --group-id "$sg" --ip-permissions "$eg" --region $REGION >/dev/null 2>&1 \
      && echo "   -> egress de $sg revocado"
  fi
done

echo "## 2) Borrando SGs"
for sg in $(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC" \
            --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text --region $REGION); do
  aws ec2 delete-security-group --group-id "$sg" --region $REGION >/dev/null 2>&1 \
    && echo "   -> SG $sg borrado" || echo "   -> $sg aun con deps"
done

echo "## 3) Borrando VPC"
if aws ec2 delete-vpc --vpc-id "$VPC" --region $REGION >/dev/null 2>&1; then
  echo ">>> VPC BORRADA — LIMPIO TOTAL ✅"
else
  echo ">>> VPC aun con dependencias. Pega la salida de abajo:"
  echo "-- SGs restantes:"
  aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC" --query 'SecurityGroups[].{id:GroupId,name:GroupName}' --output table --region $REGION
  echo "-- ENIs restantes:"
  aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC" --query 'NetworkInterfaces[].{id:NetworkInterfaceId,status:Status,desc:Description}' --output table --region $REGION
fi
