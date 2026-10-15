#!/usr/bin/env bash
# =====================================================================
#  Teardown EP2 - borra TODA la infra huerfana (el tfstate quedo vacio)
#  Corre en la terminal donde estan cargadas las credenciales del lab.
#  Es idempotente: si algo ya no existe, lo ignora y sigue.
# =====================================================================
REGION=us-east-1
CLUSTER=freshbox-cluster
RDS=freshbox-mysql
VPC_NAME=freshbox-vpc
DBSUBNET=freshbox-db-subnet

echo "############ 1/9  RDS: solicitando borrado de $RDS ############"
aws rds delete-db-instance --db-instance-identifier "$RDS" \
  --skip-final-snapshot --delete-automated-backups --region $REGION >/dev/null 2>&1 \
  && echo "   -> borrado solicitado" || echo "   -> ya no existe (sigo)"

echo "############ 2/9  EKS node groups ############"
for ng in $(aws eks list-nodegroups --cluster-name "$CLUSTER" --region $REGION \
            --query 'nodegroups[]' --output text 2>/dev/null); do
  [ "$ng" = "None" ] && continue
  echo "   borrando nodegroup $ng ..."
  aws eks delete-nodegroup --cluster-name "$CLUSTER" --nodegroup-name "$ng" --region $REGION >/dev/null 2>&1
  aws eks wait nodegroup-deleted --cluster-name "$CLUSTER" --nodegroup-name "$ng" --region $REGION 2>/dev/null
  echo "   -> $ng borrado"
done

echo "############ 3/9  EKS cluster (esto tarda ~8 min) ############"
aws eks delete-cluster --name "$CLUSTER" --region $REGION >/dev/null 2>&1 \
  && aws eks wait cluster-deleted --name "$CLUSTER" --region $REGION 2>/dev/null
echo "   -> cluster borrado"

echo "############ 4/9  Esperando a que RDS termine de borrarse (~8 min) ############"
aws rds wait db-instance-deleted --db-instance-identifier "$RDS" --region $REGION 2>/dev/null
echo "   -> RDS borrada"
aws rds delete-db-subnet-group --db-subnet-group-name "$DBSUBNET" --region $REGION >/dev/null 2>&1 \
  && echo "   -> db subnet group borrado"

VPC=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" \
      --query 'Vpcs[0].VpcId' --output text --region $REGION 2>/dev/null)
echo "############ VPC encontrada: $VPC ############"
if [ "$VPC" = "None" ] || [ -z "$VPC" ]; then
  echo ">>> No hay VPC que borrar. LISTO."
else
  echo "############ 5/9  NAT gateways ############"
  for nat in $(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC" \
               "Name=state,Values=available,pending" \
               --query 'NatGateways[].NatGatewayId' --output text --region $REGION 2>/dev/null); do
    echo "   borrando NAT $nat ..."
    aws ec2 delete-nat-gateway --nat-gateway-id "$nat" --region $REGION >/dev/null 2>&1
  done
  echo "   esperando a que el NAT muera..."
  for i in $(seq 1 30); do
    left=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC" \
           "Name=state,Values=available,pending,deleting" \
           --query 'length(NatGateways)' --output text --region $REGION 2>/dev/null)
    [ "$left" = "0" ] && break
    sleep 15
  done
  echo "   -> NAT fuera"

  echo "############ 6/9  Liberando Elastic IP ############"
  for alloc in $(aws ec2 describe-addresses --filters "Name=tag:Name,Values=freshbox-eip-nat" \
                 --query 'Addresses[].AllocationId' --output text --region $REGION 2>/dev/null); do
    [ "$alloc" = "None" ] && continue
    aws ec2 release-address --allocation-id "$alloc" --region $REGION >/dev/null 2>&1 \
      && echo "   -> liberada $alloc"
  done

  echo "############ 7/9  ENIs sueltas ############"
  for eni in $(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC" \
               --query 'NetworkInterfaces[?Status==`available`].NetworkInterfaceId' \
               --output text --region $REGION 2>/dev/null); do
    aws ec2 delete-network-interface --network-interface-id "$eni" --region $REGION >/dev/null 2>&1 \
      && echo "   -> ENI $eni borrada"
  done

  echo "############ 8/9  Subnets / route tables / SGs / IGW ############"
  for sub in $(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC" \
               --query 'Subnets[].SubnetId' --output text --region $REGION 2>/dev/null); do
    aws ec2 delete-subnet --subnet-id "$sub" --region $REGION >/dev/null 2>&1 \
      && echo "   -> subnet $sub borrada"
  done
  for rt in $(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC" \
              --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' \
              --output text --region $REGION 2>/dev/null); do
    aws ec2 delete-route-table --route-table-id "$rt" --region $REGION >/dev/null 2>&1 \
      && echo "   -> route table $rt borrada"
  done
  # SGs: reintenta 5 veces (cadena alb->nodes->data se resuelve al borrar en orden)
  for pass in 1 2 3 4 5; do
    for sg in $(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC" \
                --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
                --output text --region $REGION 2>/dev/null); do
      aws ec2 delete-security-group --group-id "$sg" --region $REGION >/dev/null 2>&1 \
        && echo "   -> SG $sg borrado"
    done
  done
  for igw in $(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC" \
               --query 'InternetGateways[].InternetGatewayId' --output text --region $REGION 2>/dev/null); do
    aws ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$VPC" --region $REGION >/dev/null 2>&1
    aws ec2 delete-internet-gateway --internet-gateway-id "$igw" --region $REGION >/dev/null 2>&1 \
      && echo "   -> IGW $igw borrado"
  done

  echo "############ 9/9  VPC (reintenta hasta que suelten las dependencias) ############"
  for try in 1 2 3 4 5 6; do
    if aws ec2 delete-vpc --vpc-id "$VPC" --region $REGION >/dev/null 2>&1; then
      echo "   -> VPC $VPC borrada"
      break
    fi
    echo "   intento $try: aun con dependencias, espero 20s..."
    sleep 20
  done
fi

echo ""
echo "################## VERIFICACION FINAL ##################"
echo "-- Clusters EKS (debe salir vacio []):"
aws eks list-clusters --region $REGION
echo "-- RDS (debe salir vacio []):"
aws rds describe-db-instances --region $REGION --query 'DBInstances[].DBInstanceIdentifier'
echo "-- VPC freshbox (debe salir None):"
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query 'Vpcs[0].VpcId' --output text --region $REGION
echo "####################### FIN #######################"
