# Django App — End-to-End CI/CD on AWS

A production-ready Django REST API deployed with a full CI/CD pipeline using Docker, Jenkins, Terraform, Kubernetes (EKS), ArgoCD, and GitHub Actions.

---

## Stack

| Layer | Tool |
|---|---|
| Application | Django 4.2 + Django REST Framework |
| Database | PostgreSQL 15 |
| Cache / Queue | Redis + Celery |
| Containerization | Docker + Docker Compose |
| CI/CD | Jenkins + GitHub Actions |
| Infrastructure | Terraform (AWS EC2) |
| Orchestration | Kubernetes on AWS EKS |
| Continuous Delivery | ArgoCD |
| Security Scanning | Trivy + SonarQube |

---

## Project Structure

```
django-app-deployment/
├── manage.py
├── requirements.txt
├── Dockerfile
├── docker-compose.yml
├── Makefile
├── gunicorn-cfg.py
├── .env.example
│
├── multitenantsaas/          ← Django project config
│   ├── settings.py
│   ├── urls.py
│   ├── wsgi.py
│   └── celery.py
│
├── apps/
│   ├── app/                  ← REST API app  →  /api/health/
│   └── home/                 ← Homepage app  →  /
│
└── deployments/
    ├── k8s/                  ← Kubernetes manifests
    ├── terraform/            ← AWS EC2 provisioning
    ├── jenkins/              ← Jenkinsfile pipeline
    └── .github/workflows/    ← GitHub Actions workflows
```

---

## Quick Start (Local)

```bash
# 1. Clone the repo
git clone https://github.com/cojocloud/django-app-deployment.git
cd django-app-deployment

# 2. Copy environment file and fill in your values
cp .env.example .env

# 3. Start all services
make up

# App        → http://localhost:8585
# API health → http://localhost:8585/api/health/
# pgAdmin    → http://localhost:5051  (admin@admin.com / admin)
```

---

## Endpoints

| URL | Description |
|---|---|
| `GET /` | Homepage — returns app status |
| `GET /api/health/` | Health check — returns `{"status": "ok"}` |
| `GET /admin/` | Django admin panel |

---

## GitHub Required Secrets

Add these in **Settings → Secrets and Variables → Actions**:

| Secret | Value |
|---|---|
| `AWS_ACCESS_KEY_ID` | Your AWS access key |
| `AWS_SECRET_ACCESS_KEY` | Your AWS secret key |

---

## Makefile Commands

```bash
make venv       # Create virtual environment
make install    # Install Python dependencies
make run        # Run dev server locally
make build      # Build Docker image
make push       # Push image to Docker Hub (thiexco/django-app)
make up         # Start all services via docker-compose
make down       # Stop all services
make migrate    # Run migrations inside running container
```

---

## Jenkins Credentials Required

Add these inside Jenkins → Manage Jenkins → Credentials:

| ID | Type | Value |
|---|---|---|
| `dockerhub-credentials` | Username + Password | Docker Hub login (thiexco) |
| `aws-access-key-id` | Secret text | AWS access key |
| `aws-secret-access-key` | Secret text | AWS secret key |

---

## Deployment Pipeline (Jenkins)

```
Checkout → Build Image → SonarQube → Trivy Scan → Push Image → Deploy to EKS → ArgoCD Sync
```

---

## License

MIT
