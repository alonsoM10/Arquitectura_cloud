# Infraestructura como Código — FreshBox EP1 (Terraform)

Despliega el **Diagrama B optimizado** en AWS Academy Learner Lab.

## Componentes que crea

| Archivo | Crea |
|---|---|
| `network.tf` | VPC /22, 6 subredes (3 capas × 2 AZ), IGW, tablas de rutas |
| `endpoints.tf` | VPC Endpoints (S3, ECR, Logs, Secrets) — **sin NAT** |
| `security.tf` | Security Groups encadenados ALB → APP → DATA |
| `secrets.tf` | Llave KMS |
| `rds.tf` | RDS MySQL Multi-AZ, cifrado, password gestionada |
| `ecr.tf` | 4 repositorios de imágenes |
| `ecs.tf` | Cluster Fargate, 4 servicios, autoscaling (2–4) |
| `alb.tf` | ALB + 4 target groups + reglas por método HTTP |
| `frontend.tf` | S3 + CloudFront + WAF |

## Requisitos previos

1. **Terraform** ≥ 1.5 y **Docker Desktop** instalados.
2. **AWS CLI** con las credenciales del Learner Lab en `~/.aws/credentials`
   (cópialas desde *AWS Details → AWS CLI* en el lab). **Expiran ~cada 4h.**

## Despliegue (orden)

```bash
cd infra/terraform
terraform init
terraform apply           # crea todo (RDS Multi-AZ tarda ~10-15 min)
```

```bash
# 2) Construir y subir las 4 imágenes backend
bash ../scripts/ecr-push.sh
```

### 3) Cargar datos en la BD (una sola vez)

RDS es privada. Para cargar `app/init.sql`:

```bash
# a) exponer RDS temporalmente desde tu IP
#    en terraform.tfvars:  enable_db_public_seeding = true  y  my_ip_cidr = "TU.IP/32"
terraform apply

# b) obtener credenciales y endpoint
terraform output rds_endpoint
aws secretsmanager get-secret-value --secret-id "$(terraform output -raw db_secret_arn)" --query SecretString --output text

# c) cargar el esquema + productos
mysql -h <rds_endpoint> -u admin -p freshbox < ../../app/init.sql

# d) volver a cerrar la BD
#    en terraform.tfvars:  enable_db_public_seeding = false
terraform apply
```

### 4) Probar

```bash
terraform output cloudfront_url
```

Abre esa URL → frontend con los 5 productos. El CRUD funciona vía `/api/*`.

## Al terminar (evita gastar créditos)

```bash
terraform destroy
```

## Notas del Learner Lab

- **IAM:** se usa el rol preexistente `LabRole` (no se pueden crear roles).
- **WAF:** si `terraform apply` falla en WAFv2, pon `enable_waf = false`.
- **Arquitectura de imágenes:** Fargate corre en `X86_64`; el script compila con `--platform linux/amd64`.
