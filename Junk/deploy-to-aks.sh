#!/bin/bash

# AKS Deployment Script
# Runs on the jump server to deploy the application

set -e

echo "🚀 Starting AKS deployment..."

# Verify required environment variables
required_vars=(
    "RESOURCE_GROUP_NAME"
    "AKS_CLUSTER_NAME" 
    "ACR_LOGIN_SERVER"
    "ACR_USERNAME"
    "ACR_PASSWORD"
    "IMAGE_TAG"
    "DB_HOST"
    "DB_PASSWORD"
    "APP_INSIGHTS_KEY"
    "CLOUDFLARE_API_KEY"
)

for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "❌ Error: $var is not set"
        exit 1
    fi
done


# === ADD THIS SECTION AFTER THE ENVIRONMENT VARIABLE CHECKS ===

# Check and install dependencies
echo "🔍 Checking required dependencies..."

# Check if NGINX Ingress is installed
if ! kubectl get namespace ingress-nginx &> /dev/null; then
    echo "📦 Installing NGINX Ingress Controller..."
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo update
    helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
        --namespace ingress-nginx \
        --create-namespace \
        --set controller.replicaCount=2 \
        --wait --timeout=300s
    echo "✅ NGINX Ingress Controller installed"
else
    echo "✅ NGINX Ingress Controller already exists"
fi

# Check if cert-manager is installed
if ! kubectl get namespace cert-manager &> /dev/null; then
    echo "🔐 Installing cert-manager..."
    helm repo add jetstack https://charts.jetstack.io
    helm repo update
    helm upgrade --install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --create-namespace \
        --version v1.12.0 \
        --set installCRDs=true \
        --wait --timeout=300s
    echo "✅ cert-manager installed"
else
    echo "✅ cert-manager already exists"
fi

# Create Cloudflare cluster issuer (idempotent)
echo "🌤️ Setting up Cloudflare cluster issuer..."
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: cloudflare-issuer
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@retoucherirving.com
    privateKeySecretRef:
      name: cloudflare-issuer-account-key
    solvers:
    - dns01:
        cloudflare:
          email: talk2osomudeya4devops@gmail.com
          apiKeySecretRef:
            name: cloudflare-api-key
            key: api-key
EOF

echo "✅ Dependencies ready!"


# Login to Azure (using service principal from environment)
echo "🔐 Logging into Azure..."
az login --service-principal \
    --username "$ARM_CLIENT_ID" \
    --password "$ARM_CLIENT_SECRET" \
    --tenant "$ARM_TENANT_ID"

# Get AKS credentials
echo "📋 Getting AKS credentials..."
az aks get-credentials \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --name "$AKS_CLUSTER_NAME" \
    --overwrite-existing

# Verify cluster connectivity
echo "🔍 Verifying cluster access..."
kubectl cluster-info
kubectl get nodes

# Create ACR secret for image pulling
echo "🔑 Creating ACR secret..."
kubectl create secret docker-registry acr-secret \
    --namespace=retoucherirving \
    --docker-server="$ACR_LOGIN_SERVER" \
    --docker-username="$ACR_USERNAME" \
    --docker-password="$ACR_PASSWORD" \
    --dry-run=client -o yaml | kubectl apply -f -

# Create application secrets
echo "🔒 Creating application secrets..."
kubectl create secret generic app-secrets \
    --namespace=retoucherirving \
    --from-literal=DB_HOST="$DB_HOST" \
    --from-literal=DB_NAME="webapp" \
    --from-literal=DB_USER="adminuser" \
    --from-literal=DB_PASSWORD="$DB_PASSWORD" \
    --from-literal=APPLICATIONINSIGHTS_CONNECTION_STRING="$APP_INSIGHTS_KEY" \
    --from-literal=ADMIN_KEY="$(openssl rand -base64 32)" \
    --dry-run=client -o yaml | kubectl apply -f -

echo "🗄️ Initializing database..."
DB_INIT_POD=$(kubectl get pods -n retoucherirving -l app=backend -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n retoucherirving $DB_INIT_POD -- npm run db:migrate || echo "Database already initialized"

# Create Cloudflare API secret for SSL certificates
echo "🌤️ Creating Cloudflare API secret..."
kubectl create secret generic cloudflare-api-key \
    --namespace cert-manager \
    --from-literal=api-key="$CLOUDFLARE_API_KEY" \
    --dry-run=client -o yaml | kubectl apply -f -

# Apply Kubernetes manifests
echo "📦 Applying Kubernetes manifests..."

# Apply namespace and config first
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml

# Update deployment files with current image tags
sed -i "s|image: # This will be set by CI/CD pipeline|image: ${ACR_LOGIN_SERVER}/retoucherirving/backend:${IMAGE_TAG}|g" k8s/backend-deployment.yaml
sed -i "s|image: # This will be set by CI/CD pipeline|image: ${ACR_LOGIN_SERVER}/retoucherirving/frontend:${IMAGE_TAG}|g" k8s/frontend-deployment.yaml

# Apply deployments and services
kubectl apply -f k8s/backend-deployment.yaml
kubectl apply -f k8s/frontend-deployment.yaml
kubectl apply -f k8s/backend-service.yaml
kubectl apply -f k8s/frontend-service.yaml

# Wait for deployments to be ready
echo "⏳ Waiting for deployments to be ready..."
kubectl rollout status deployment/backend -n retoucherirving --timeout=300s
kubectl rollout status deployment/frontend -n retoucherirving --timeout=300s

# Apply ingress
kubectl apply -f k8s/ingress.yaml

# Check deployment status
echo "📊 Deployment Status:"
kubectl get pods -n retoucherirving
kubectl get services -n retoucherirving
kubectl get ingress -n retoucherirving

# Test backend health
echo "🏥 Testing backend health..."
BACKEND_POD=$(kubectl get pods -n retoucherirving -l app=backend -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n retoucherirving $BACKEND_POD -- curl -f http://localhost:3001/health

echo "✅ Deployment completed successfully!"
echo "🌐 Application should be available at: https://retoucherirving.com"