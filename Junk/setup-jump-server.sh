#!/bin/bash

# Jump Server Setup Script
# This script installs all necessary tools on the jump server

set -e

echo "🚀 Setting up Jump Server..."

# Update system
sudo apt-get update -y
sudo apt-get upgrade -y

# Install basic tools
sudo apt-get install -y \
    curl \
    wget \
    unzip \
    git \
    jq \
    ca-certificates \
    gnupg \
    lsb-release

# Install Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Install Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io

# Add user to docker group
sudo usermod -aG docker $USER

# Install Helm
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install -y helm

# Install cert-manager CLI
curl -L -o cmctl.tar.gz https://github.com/cert-manager/cert-manager/releases/latest/download/cmctl-linux-amd64.tar.gz
tar -xzf cmctl.tar.gz
chmod +x cmctl
sudo mv cmctl /usr/local/bin
rm cmctl.tar.gz

# Create working directory
mkdir -p ~/deployments

echo "✅ Jump Server setup completed!"
echo "Installed tools:"
echo "- Azure CLI: $(az version --query '\"azure-cli\"' -o tsv)"
echo "- kubectl: $(kubectl version --client --short)"
echo "- Docker: $(docker --version)"
echo "- Helm: $(helm version --short)"

# Login to Azure (interactive - will be done during deployment)
echo "📝 Next steps:"
echo "1. Login to Azure: az login"
echo "2. Get AKS credentials: az aks get-credentials --resource-group <rg> --name <aks-name>"
echo "3. Verify cluster access: kubectl get nodes"

# Refresh current session to pick up group changes
echo "🔄 Refreshing session for group changes..."
newgrp docker << SUBSHELL
echo "✅ Jump server setup completed with fresh session!"
SUBSHELL

# Or alternatively, just log the user needs to re-login
echo "⚠️  Note: Please run 'newgrp docker' or re-login to use Docker without sudo"