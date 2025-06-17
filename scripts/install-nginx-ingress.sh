#!/bin/bash

# NGINX Ingress Controller Installation Script
# Run this on jump server to install ingress controller

set -e

echo "🚀 Installing NGINX Ingress Controller..."

# Add NGINX Ingress Helm repository
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Install NGINX Ingress Controller
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
    --namespace ingress-nginx \
    --create-namespace \
    --set controller.replicaCount=2 \
    --set controller.nodeSelector."kubernetes\.io/os"=linux \
    --set defaultBackend.nodeSelector."kubernetes\.io/os"=linux \
    --set controller.service.loadBalancerIP="" \
    --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"="/healthz" \
    --set controller.metrics.enabled=true \
    --set controller.metrics.serviceMonitor.enabled=true \
    --set controller.podAnnotations."prometheus\.io/scrape"="true" \
    --set controller.podAnnotations."prometheus\.io/port"="10254"

# Wait for NGINX Ingress to be ready
echo "⏳ Waiting for NGINX Ingress Controller to be ready..."
kubectl wait --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=300s

# Install cert-manager for SSL certificates
echo "🔐 Installing cert-manager..."
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --create-namespace \
    --version v1.12.0 \
    --set installCRDs=true \
    --set nodeSelector."kubernetes\.io/os"=linux

# Wait for cert-manager to be ready
echo "⏳ Waiting for cert-manager to be ready..."
kubectl wait --namespace cert-manager \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/name=cert-manager \
    --timeout=300s

# Create Cloudflare cluster issuer
echo "🌤️ Creating Cloudflare cluster issuer..."
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
          email: admin@retoucherirving.com
          apiKeySecretRef:
            name: cloudflare-api-key
            key: api-key
EOF

echo "⚠️  Important: Create Cloudflare API secret before certificates will work:"
echo "   export CLOUDFLARE_API_KEY='your-api-key'"
echo "   ./setup-cloudflare-ssl.sh"

# Get external IP of ingress controller
echo "📋 Getting NGINX Ingress external IP..."
kubectl get service -n ingress-nginx ingress-nginx-controller

echo "✅ NGINX Ingress Controller installation completed!"
echo "📝 Next steps:"
echo "1. Update your DNS to point to the external IP"
echo "2. Create the Cloudflare API key secret if using Cloudflare"
echo "3. Apply your ingress manifests"

# Show useful commands
echo ""
echo "Useful commands:"
echo "- View ingress status: kubectl get ingress -A"
echo "- View certificates: kubectl get certificates -A"
echo "- View ingress logs: kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx"