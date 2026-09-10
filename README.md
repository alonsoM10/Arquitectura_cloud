# Arquitectura Cloud — FreshBox SpA (EP1 · ARY1102)

Plataforma de **catálogo online de productos orgánicos** para FreshBox SpA.
Arquitectura cloud en AWS, escalable, segura y de alta disponibilidad (Multi-AZ),
desplegada con **Infraestructura como Código (Terraform)**.

> Evaluación Parcial 1 (40%) — Arquitectura Cloud, Duoc UC. Caso FreshBox SpA.

---

## 📐 Dos arquitecturas (por qué)

Este repo documenta **dos diseños** de forma deliberada:

| | Diagrama A — Base pauta | Diagrama B — Optimizado (implementado) |
|---|---|---|
| Frontend | Contenedor Nginx | **S3 + CloudFront** (estático + HTTPS) |
| App | EC2 + Docker + Auto Scaling Group | **ECS Fargate** + Service Auto Scaling |
| Base de datos | EC2 + MySQL | **RDS MySQL Multi-AZ** (gestionado, KMS) |
| Salida privada | NAT Gateway | **VPC Endpoints** (ECR / S3) |
| Seguridad extra | Security Groups | **WAF + Secrets Manager + KMS** |

**Diagrama A** cumple los componentes exactos que exige la rúbrica.
**Diagrama B** es la optimización justificada por el *Well-Architected Framework*
(más barato, más seguro, menos operación) y es la que se implementa como IaC.

Diagramas en [`docs/diagramas/`](docs/diagramas/).

---

## 🗂️ Estructura del repositorio

```
Arquitectura_cloud/
├── app/                     # Aplicación base (5 microservicios del caso)
│   ├── docker-compose.yml   # Prueba local
│   ├── init.sql             # BD freshbox + 5 productos
│   ├── microservicioFrontend/
│   └── microserviciosBackend/  (get / create / update / delete-product)
├── infra/
│   └── terraform/           # IaC del Diagrama B (en construcción)
├── docs/
│   ├── diagramas/           # Diagrama_B_optimizado.drawio
│   └── EP1_ARY1102_Estudiante.pdf
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

## 🧩 Microservicios

| Contenedor | Puerto | Endpoint | Método |
|------------|--------|----------|--------|
| frontend | 80 | `/` | — |
| get-products | 3001 | `/api/products` | GET |
| create-product | 3002 | `/api/products` | POST |
| update-product | 3003 | `/api/products/:id` | PUT |
| delete-product | 3004 | `/api/products/:id` | DELETE |

---

## 🛣️ Roadmap

- [x] Base de la aplicación (microservicios del caso)
- [x] Diagrama B optimizado (draw.io)
- [ ] IaC Terraform: red (VPC /22, 6 subredes, VPC Endpoints)
- [ ] IaC: Security Groups encadenados (ALB → APP → DATA)
- [ ] IaC: RDS MySQL Multi-AZ + Secrets Manager + KMS
- [ ] IaC: ECS Fargate + ALB + autoscaling
- [ ] IaC: S3 + CloudFront + WAF (frontend)
- [ ] Informe técnico (puntos 1.1 – 1.7)
- [ ] Presentación + demo AWS Academy
