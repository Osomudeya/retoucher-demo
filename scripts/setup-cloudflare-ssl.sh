#!/bin/bash

# Cloudflare SSL Setup Script
# Run this AFTER installing NGINX Ingress Controller

set -e

echo "🌤️ Setting up Cloudflare SSL configuration..."

# Check if Cloudflare API key is provided
if [ -z "$CLOUDFLARE_API_KEY" ]; then
    echo "❌ Error: CLOUDFLARE_API_KEY environment variable not set"
    echo "Get your API key from: https://dash.cloudflare.com/profile/api-tokens"
    exit 1
fi

# Create Cloudflare API key secret
echo "🔑 Creating Cloudflare API key secret..."
kubectl create secret generic cloudflare-api-key \
    --from-literal=api-key="$CLOUDFLARE_API_KEY" \
    --namespace cert-manager \
    --dry-run=client -o yaml | kubectl apply -f -

# Verify cert-manager is ready
echo "🔍 Verifying cert-manager is ready..."
kubectl wait --namespace cert-manager \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/name=cert-manager \
    --timeout=300s

echo "✅ Cloudflare SSL setup completed!"
echo "📝 Next steps:"
echo "1. Update your DNS A record to point to the ingress external IP"
echo "2. Apply your ingress manifests with TLS configuration"
echo "3. Wait for certificates to be issued (check with: kubectl get certificates -A)"