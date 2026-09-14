# Arquitectura Cloud — FreshBox SpA (EP1 · ARY1102)

Plataforma de **catálogo online de productos orgánicos** para FreshBox SpA.
Arquitectura cloud en AWS, escalable, segura y de alta disponibilidad (Multi-AZ),
desplegada con **Infraestructura como Código (Terraform)** y **CI/CD (GitHub Actions)**.

> Evaluación Parcial 1 (40%) — Arquitectura Cloud, Duoc UC. Caso FreshBox SpA.

---

## 📐 Dos arquitecturas (por qué)

Este repo documenta **dos diseños** de forma deliberada:

| | Diagrama A — Base pauta | Diagrama B — Optimizado (implementado) |
|---|---|---|
| Frontend | Contenedor Nginx | **Contenedor Nginx en ECS Fargate** tras el ALB |
| App | EC2 + Docker + Auto Scaling Group | **ECS Fargate** + Service Auto Scaling |
| Base de datos | EC2 + MySQL | **RDS MySQL Multi-AZ** (gestionado, KMS) |
| Salida privada | NAT Gateway | **VPC Endpoints** (ECR / S3 / logs / secrets) |
| Seguridad extra | Security Groups | **Secrets Manager + KMS** + SG encadenados |

**Diagrama A** cumple los componentes exactos que exige la rúbrica.
**Diagrama B** es la optimización justificada por el *Well-Architected Framework*
(más barato, más seguro, menos operación) y es la que se implementa como IaC.

> **Nota:** el diseño original contemplaba **S3 + CloudFront + WAF** para el frontend.
> La *Service Control Policy* del AWS Academy Learner Lab bloquea CloudFront, por lo que
> el frontend se sirve como un **quinto contenedor Nginx en Fargate** detrás del ALB.
> Ver detalle en el informe técnico (sección 9, Limitaciones del entorno).

Diagramas en [`docs/diagramas/`](docs/diagramas/).

---

## 🗂️ Estructura del repositorio

```
Arquitectura_cloud/
├── app/                       # Aplicación base (5 microservicios del caso)
│   ├── docker-compose.yml     # Prueba local
│   ├── init.sql               # BD freshbox + 5 productos
│   ├── microservicioFrontend/     # Nginx (sirve el catálogo)
│   └── microserviciosBackend/     # get / create / update / delete-product
├── infra/
│   ├── terraform/             # IaC del Diagrama B (red, RDS, ECS, ALB, etc.)
│   └── scripts/               # ecr-push.sh (build+push) · seed-db.sh (carga BD)
├── docs/
│   └── diagramas/             # Diagrama_B_optimizado.drawio
├── .github/workflows/         # CI/CD: deploy.yml · destroy.yml
└── README.md
```

---

## 🚀 Prueba local (Docker)

```bash
cd app
docker compose build
docker compose up -d
docker compose ps
```

- Frontend: http://localhost:8080
- API productos: http://localhost:3001/api/products

Detener:

```bash
docker compose down -v
```

---

## ☁️ Despliegue en AWS (CI/CD con GitHub Actions)

Todo el ciclo se ejecuta con **un clic** desde la pestaña **Actions**, sin instalar nada local.

1. Inicia el **AWS Academy Learner Lab** y copia las credenciales (AWS Details → AWS CLI).
2. En el repo → **Settings → Secrets and variables → Actions**, define/actualiza:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
   - `AWS_SESSION_TOKEN`
3. **Actions → Deploy → Run workflow.** Aprovisiona la infra con Terraform, construye y
   publica las 5 imágenes en **ECR**, siembra la BD y expone la **URL del ALB**.
4. Al terminar de capturar evidencia → **Actions → Destroy → Run workflow** para
   apagar toda la infraestructura y no gastar presupuesto.

> Cada Learner Lab es una cuenta nueva y las credenciales son temporales (~4 h);
> por eso `Deploy` parte de un estado fresco y el `tfstate` se guarda como artifact
> para que `Destroy` pueda leerlo.

### Despliegue local (alternativa)

```bash
cd infra/terraform
terraform init
terraform apply
bash ../scripts/ecr-push.sh   # build + push de las 5 imágenes a ECR
bash ../scripts/seed-db.sh    # carga init.sql en la RDS privada
terraform output app_url
```

---

## 🧩 Microservicios

| Contenedor | Puerto | Endpoint | Método |
|------------|--------|----------|--------|
| frontend | 80 | `/` | — |
| get-products | 3001 | `/api/products` | GET |
| create-product | 3002 | `/api/products` | POST |
| update-product | 3003 | `/api/products/:id` | PUT |
| delete-product | 3004 | `/api/products/:id` | DELETE |

El **ALB** enruta hacia cada microservicio según la ruta y el método HTTP.

---

## ✅ Estado del proyecto

- [x] Base de la aplicación (microservicios del caso)
- [x] Diagrama B optimizado (draw.io)
- [x] IaC Terraform: red (VPC /22, 6 subredes Multi-AZ, VPC Endpoints)
- [x] IaC: Security Groups encadenados (ALB → APP → DATA)
- [x] IaC: RDS MySQL Multi-AZ + Secrets Manager + KMS
- [x] IaC: ECS Fargate + ALB + Service Auto Scaling
- [x] IaC: frontend Nginx en Fargate (adaptación por SCP; ver informe)
- [x] CI/CD: GitHub Actions (Deploy / Destroy)
- [x] Informe técnico (puntos 1.1 – 1.7 + CI/CD + limitaciones)
- [x] Despliegue funcional validado end-to-end (catálogo + CRUD)
