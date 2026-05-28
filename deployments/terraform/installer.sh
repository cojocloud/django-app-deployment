#!/bin/bash
set -e

# Wait for cloud-init to finish, then release apt locks held by unattended-upgrades
echo "Waiting for cloud-init..."
cloud-init status --wait 2>/dev/null || true

echo "Stopping unattended-upgrades..."
sudo systemctl disable --now unattended-upgrades 2>/dev/null || true
sudo killall apt apt-get dpkg 2>/dev/null || true

echo "Waiting for apt locks..."
while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
      sudo fuser /var/lib/apt/lists/lock    >/dev/null 2>&1 || \
      sudo fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
  echo "  still locked — retrying in 5s..."
  sleep 5
done

sudo dpkg --configure -a 2>/dev/null || true
sudo apt-get update -y

echo "Installing base tools..."

sudo apt-get install -y \
curl wget git unzip zip jq \
build-essential software-properties-common \
ca-certificates gnupg lsb-release \
python3 python3-pip openjdk-21-jdk

########################################
# Jenkins
########################################

if ! command -v jenkins >/dev/null 2>&1; then

  echo "Installing Jenkins..."

  if [ ! -f /usr/share/keyrings/jenkins-keyring.asc ]; then
    curl -fsSL https://pkg.jenkins.io/debian/jenkins.io-2026.key | \
      sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
  fi

  if [ ! -f /etc/apt/sources.list.d/jenkins.list ]; then
    echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian binary/" | \
      sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
  fi

  sudo apt-get update -y
  sudo apt-get install -y jenkins

fi

sudo systemctl enable --now jenkins

########################################
# Docker
########################################

if ! command -v docker >/dev/null 2>&1; then

  echo "Installing Docker..."

  sudo install -m 0755 -d /etc/apt/keyrings

  if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
      sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  fi

  if [ ! -f /etc/apt/sources.list.d/docker.list ]; then
    echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu \
$(lsb_release -cs) stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  fi

  sudo apt-get update -y

  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

fi

sudo groupadd -f docker
sudo usermod -aG docker ubuntu || true
sudo usermod -aG docker jenkins || true

sudo systemctl enable --now docker

sudo chmod 777 /var/run/docker.sock
sudo curl -L "https://github.com/docker/compose/releases/download/v2.23.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

########################################
# Trivy
########################################

if ! command -v trivy >/dev/null 2>&1; then

  echo "Installing Trivy..."

  if [ ! -f /usr/share/keyrings/trivy.gpg ]; then
    wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | \
      gpg --dearmor | \
      sudo tee /usr/share/keyrings/trivy.gpg > /dev/null
  fi

  if [ ! -f /etc/apt/sources.list.d/trivy.list ]; then
    echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" | \
      sudo tee /etc/apt/sources.list.d/trivy.list
  fi

  sudo apt-get update
  sudo apt-get install -y trivy

fi

echo "=== Installing AWS CLI ==="
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

echo "=== Installing kubectl ==="
curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.27.1/2023-04-19/bin/linux/amd64/kubectl
chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin/kubectl

echo "=== Installing eksctl ==="
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

echo "=== Installing ArgoCD CLI ==="
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64

echo "=== All tools installed successfully ==="
