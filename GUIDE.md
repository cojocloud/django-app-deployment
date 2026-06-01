# End-to-End Implementation Guide

This guide walks you through every step to go from zero to a fully deployed Django application on AWS EKS with a complete CI/CD pipeline. Follow the chapters in order.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Run the App Locally](#2-run-the-app-locally)
3. [Build and Push the Docker Image](#3-build-and-push-the-docker-image)
4. [Set Up AWS](#4-set-up-aws)
5. [Provision EC2 Manually](#5-provision-ec2-manually)
6. [Install Jenkins on EC2](#6-install-jenkins-on-ec2)
7. [Configure Jenkins Pipeline](#7-configure-jenkins-pipeline)
8. [Create the EKS Cluster](#8-create-the-eks-cluster)
9. [Deploy with kubectl](#9-deploy-with-kubectl)
10. [Set Up ArgoCD](#10-set-up-argocd)
11. [Add SonarQube (Code Quality)](#11-add-sonarqube-code-quality)
12. [Trivy Security Scan](#12-trivy-security-scan)
13. [Clean Up All Resources](#13-clean-up-all-resources)

---

## 1. Prerequisites

Install these tools on your local machine before starting.

### Required tools

| Tool | Install |
|---|---|
| Python 3.11+ | https://python.org |
| Docker Desktop | https://docker.com |
| AWS CLI | `brew install awscli` |
| kubectl | `brew install kubectl` |
| eksctl | `brew install eksctl` |
| ArgoCD CLI | `brew install argocd` |
| Git | `brew install git` |

### Configure AWS CLI

```bash
aws configure
# Enter your AWS Access Key ID
# Enter your AWS Secret Access Key
# Default region: us-east-1
# Default output: json
```

Verify it works:

```bash
aws sts get-caller-identity
```

---

## 2. Run the App Locally

### Option A — With Docker Compose (recommended)

```bash
# Copy the environment file
cp .env.example .env

# Start everything (Django + Postgres + Redis + Celery + pgAdmin)
make up
```

Visit:
- App: http://localhost:8585
- API: http://localhost:8585/api/health/
- Admin: http://localhost:8585/admin/
- pgAdmin: http://localhost:5051 → email: `admin@admin.com`, password: `admin`

To stop:

```bash
make down
```

### Option B — Without Docker (raw Python)

```bash
# Create and activate virtual environment
make venv
source venv/bin/activate

# Install dependencies
make install

# You need a running Postgres instance for this to work.
# Update .env with POSTGRES_HOST=localhost then run:
make run
```

### Run migrations manually inside the container

```bash
make migrate
```

### Create a Django superuser

```bash
docker exec -it django-web python manage.py createsuperuser
```

---

## 3. Build and Push the Docker Image

### Build the image

```bash
make build
# This runs: docker build -t thiexco/django-app:latest .
```

### Log in to Docker Hub

```bash
docker login -u thiexco
# Enter your Docker Hub password or access token when prompted
```

### Push the image

```bash
make push
# This runs: docker push thiexco/django-app:latest
```

Your image is now available at `docker.io/thiexco/django-app:latest`.

---

## 4. Set Up AWS

### 4.1 Create AWS Access Keys

1. Go to AWS Console → top-right menu → **Security credentials**
2. Scroll to **Access keys** → click **Create access key**
3. Download or copy the **Access Key ID** and **Secret Access Key**
4. Run `aws configure` and paste them in

### 4.2 Create an EC2 Key Pair

You need this to SSH into your EC2 instance.

```bash
aws ec2 create-key-pair \
  --key-name django-app-key \
  --query 'KeyMaterial' \
  --output text > ~/.ssh/django-app-key.pem

chmod 400 ~/.ssh/django-app-key.pem
```

---

## 5. Provision EC2 Manually

Create the EC2 instance from the AWS Console.

### 5.1 Launch the instance

1. Go to **AWS Console → EC2 → Instances → Launch instances**
2. **Name:** `django-app-ec2`
3. **AMI:** Ubuntu Server 22.04 LTS (64-bit x86)
4. **Instance type:** `t2.micro` (free tier) or larger
5. **Key pair:** select `django-app-key` (created in step 4.2)

### 5.2 Configure the security group

Create a new security group named `django-app-sg` with these inbound rules:

| Port | Protocol | Source | Purpose |
|---|---|---|---|
| 22 | TCP | 0.0.0.0/0 | SSH |
| 80 | TCP | 0.0.0.0/0 | HTTP |
| 8080 | TCP | 0.0.0.0/0 | Jenkins |
| 8585 | TCP | 0.0.0.0/0 | Django app |

### 5.3 Attach an IAM instance profile (optional but recommended)

This allows SSM Session Manager access so you can connect without SSH:

1. Go to **IAM → Roles → Create role**
2. Trusted entity: **EC2**
3. Attach policy: `AmazonSSMManagedInstanceCore`
4. Name the role `django-app-ec2-ssm-role`
5. In the EC2 launch wizard under **Advanced details → IAM instance profile**, select this role

### 5.4 Configure storage

Set root volume to **30 GB, gp3**.

### 5.5 Launch and note the public IP

Click **Launch instance**. Once it reaches the **Running** state, copy the **Public IPv4 address** — you'll need it in the next steps.

---

## 6. Install Jenkins on EC2

The `deployments/scripts/installer.sh` script installs Java, Jenkins, Docker, Trivy, AWS CLI, kubectl, eksctl, and ArgoCD CLI in one shot.

### 6.1 Copy the installer to your EC2 instance

```bash
scp -i ~/.ssh/django-app-key.pem \
  deployments/scripts/installer.sh \
  ubuntu@<EC2_PUBLIC_IP>:/tmp/installer.sh
```

### 6.2 SSH in and run the installer

```bash
ssh -i ~/.ssh/django-app-key.pem ubuntu@<EC2_PUBLIC_IP>

sudo bash /tmp/installer.sh
```

The script takes a few minutes. When it finishes you will see `=== All tools installed successfully ===`.

### 6.3 Verify Jenkins is running

```bash
sudo systemctl status jenkins
```

### 6.4 Get the initial Jenkins password

```bash
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

### 6.5 Open Jenkins in your browser

Go to `http://<EC2_PUBLIC_IP>:8080` and paste the password.

Follow the setup wizard:
- Click **Install suggested plugins**
- Create your admin user
- Set the Jenkins URL (use the EC2 IP)

### 6.6 Install extra plugins

Go to **Manage Jenkins → Plugins → Available plugins** and install:

- Docker Pipeline
- SonarQube Scanner
- Kubernetes CLI
- Git

---

## 7. Configure Jenkins Pipeline

### 7.1 Add credentials to Jenkins

Go to **Manage Jenkins → Credentials → System → Global credentials → Add Credentials**

Add the following:

**Docker Hub:**
- Kind: Username with password
- Username: `thiexco`
- Password: your Docker Hub access token
- ID: `dockerhub-credentials`

**AWS (for EKS):**
- Kind: Secret text
- ID: `aws-access-key-id` — value: your AWS access key
- ID: `aws-secret-access-key` — value: your AWS secret key

### 7.2 Create a new Jenkins job

1. Click **New Item**
2. Enter a name: `django-app-pipeline`
3. Select **Pipeline** → click OK
4. Under **Pipeline**, set **Definition** to `Pipeline script from SCM`
5. SCM: Git
6. Repository URL: `https://github.com/cojocloud/django-app-deployment.git`
7. Script Path: `deployments/jenkins/Jenkinsfile`
8. Click **Save**

### 7.3 Add a GitHub webhook (auto-trigger on push)

In your GitHub repo → **Settings → Webhooks → Add webhook**

- Payload URL: `http://<EC2_PUBLIC_IP>:8080/github-webhook/`
- Content type: `application/json`
- Events: select **Just the push event**
- Click **Add webhook**

Now every `git push` to `main` will automatically trigger the Jenkins pipeline.

### 7.4 Run the pipeline manually

Click **Build Now** to trigger your first build. The pipeline runs these stages:

```
Checkout → Build Image → SonarQube → Trivy Scan → Push Image → Deploy to EKS → ArgoCD Sync
```

---

## 8. Create the EKS Cluster

Run this from your EC2 instance (after SSHing in) or locally if you have eksctl installed.

```bash
eksctl create cluster \
  --name django-cluster \
  --nodegroup-name ng-workers \
  --node-type t3.medium \
  --nodes 2 \
  --nodes-min 1 \
  --nodes-max 3 \
  --region us-east-1
```

This takes about 15–20 minutes. It creates a CloudFormation stack in your AWS account.

### Verify the cluster

```bash
kubectl get nodes
```

You should see 2 nodes in `Ready` state.

### Update your kubeconfig

```bash
aws eks --region us-east-1 update-kubeconfig --name django-cluster
```

---

## 9. Deploy with kubectl

### Create a secret for database credentials

```bash
kubectl create secret generic django-secrets \
  --from-literal=postgres-user=postgres \
  --from-literal=postgres-password=postgres \
  --namespace=default
```

### Apply the Kubernetes manifests

```bash
kubectl apply -f deployments/k8s/deployment.yaml
kubectl apply -f deployments/k8s/service.yaml
```

### Check the deployment status

```bash
kubectl get pods
kubectl get services
```

### Get the Load Balancer URL

```bash
kubectl get svc django-app-service
```

Copy the `EXTERNAL-IP` value — that is your public app URL.

---

## 10. Set Up ArgoCD

ArgoCD watches your GitHub repo and automatically applies changes to the cluster whenever you push new Kubernetes manifests.

### 10.1 Install ArgoCD in the cluster

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Wait for all pods to be ready:

```bash
kubectl get pods -n argocd
```

### 10.2 Expose ArgoCD with a Load Balancer

```bash
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
```

Get the URL:

```bash
kubectl get svc argocd-server -n argocd
```

### 10.3 Get the initial admin password

```bash
argocd admin initial-password -n argocd
```

### 10.4 Log in via CLI

```bash
argocd login <ARGOCD_EXTERNAL_IP> --insecure --username=admin --password=<PASSWORD_FROM_ABOVE>
```

### 10.5 Create the ArgoCD application

```bash
argocd app create django-app \
  --repo https://github.com/cojocloud/django-app-deployment.git \
  --path deployments/k8s \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace default \
  --sync-policy automated
```

ArgoCD will now automatically sync every time you push changes to `deployments/k8s/`.

### 10.6 Open the ArgoCD web UI

Go to `http://<ARGOCD_EXTERNAL_IP>` in your browser. Log in with `admin` and the password from step 10.3.

---

## 11. Add SonarQube (Code Quality)

SonarQube scans your code for bugs, vulnerabilities, and code smells before the image is built.

### 11.1 Install SonarQube on the EC2 instance

SSH into EC2 and run:

```bash
# Install prerequisites
sudo apt-get install -y postgresql postgresql-contrib

# Create SonarQube database
sudo -u postgres psql -c "CREATE USER sonar WITH PASSWORD 'sonar';"
sudo -u postgres psql -c "CREATE DATABASE sonarqube OWNER sonar;"

# Download and install SonarQube
sudo wget https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-9.8.0.63668.zip -P /opt
sudo unzip /opt/sonarqube-9.8.0.63668.zip -d /opt
sudo mv /opt/sonarqube-9.8.0.63668 /opt/sonarqube

# Create sonar user
sudo groupadd sonar
sudo useradd -d /opt/sonarqube -g sonar sonar
sudo chown -R sonar:sonar /opt/sonarqube
```

Configure the database connection:

```bash
sudo nano /opt/sonarqube/conf/sonar.properties
```

Add these lines:

```
sonar.jdbc.username=sonar
sonar.jdbc.password=sonar
sonar.jdbc.url=jdbc:postgresql://localhost:5432/sonarqube
```

Create a systemd service:

```bash
sudo nano /etc/systemd/system/sonar.service
```

Paste:

```
[Unit]
Description=SonarQube service
After=syslog.target network.target

[Service]
Type=forking
ExecStart=/opt/sonarqube/bin/linux-x86-64/sonar.sh start
ExecStop=/opt/sonarqube/bin/linux-x86-64/sonar.sh stop
User=sonar
Group=sonar
Restart=always

[Install]
WantedBy=multi-user.target
```

Start the service:

```bash
sudo systemctl enable sonar
sudo systemctl start sonar
```

Access SonarQube at `http://<EC2_PUBLIC_IP>:9000` — default login: `admin` / `admin`.

### 11.2 Connect SonarQube to Jenkins

1. In SonarQube: go to **Administration → Security → Users** → create a token → copy it
2. In Jenkins: go to **Manage Jenkins → System → SonarQube servers**
   - Name: `SonarQube Server`
   - URL: `http://localhost:9000`
   - Auth token: add the token as a **Secret text** credential

The `SonarQube Analysis` stage in the Jenkinsfile will now run automatically.

---

## 12. Trivy Security Scan

Trivy scans your Docker image for known CVEs before it is pushed to Docker Hub.

Trivy is already installed by `installer.sh`. Verify it is available:

```bash
trivy --version
```

The `Trivy Scan` stage in the Jenkinsfile runs this command automatically:

```bash
trivy image thiexco/django-app:latest
```

If critical vulnerabilities are found, the pipeline will fail and the image will not be pushed.

---

## 13. Clean Up All Resources

Run these when you are done to avoid AWS charges.

### Delete the EKS cluster

```bash
eksctl delete cluster --name django-cluster --region us-east-1
```

### Delete Kubernetes resources

```bash
kubectl delete -f deployments/k8s/deployment.yaml
kubectl delete -f deployments/k8s/service.yaml
kubectl delete namespace argocd
```

### Terminate the EC2 instance

1. Go to **AWS Console → EC2 → Instances**
2. Select `django-app-ec2`
3. Click **Instance state → Terminate instance**

---

## Troubleshooting

### Docker Compose — port already in use

```bash
# Find what is using the port
lsof -i :8585

# Kill it or change the port in docker-compose.yml
```

### Django — database connection refused

Make sure the `postgres` container is running:

```bash
docker ps
docker logs django-postgres
```

### kubectl — cannot connect to cluster

Re-run the kubeconfig update:

```bash
aws eks --region us-east-1 update-kubeconfig --name django-cluster
```

### Jenkins pipeline fails at Docker push

Make sure the `dockerhub-credentials` credential in Jenkins uses your Docker Hub **access token**, not your password. Generate one at https://hub.docker.com → Account Settings → Security → Access Tokens.
