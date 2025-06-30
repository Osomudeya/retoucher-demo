#!/bin/bash

# Install Cluster Dependencies
# Installs NGINX Ingress Controller and cert-manager

set -euo pipefail

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to wait for deployment to be ready
wait_for_deployment() {
    local namespace=$1
    local deployment=$2
    local timeout=${3:-300}
    
    log "Waiting for deployment $deployment in namespace $namespace to be ready..."
    
    if kubectl wait --namespace "$namespace" \
        --for=condition=available deployment "$deployment" \
        --timeout="${timeout}s"; then
        log "Deployment $deployment is ready"
        return 0
    else
        log "ERROR: Deployment $deployment failed to become ready within ${timeout}s"
        return 1
    fi
}

# Function to wait for pods to be ready
wait_for_pods() {
    local namespace=$1
    local selector=$2
    local timeout=${3:-300}
    
    log "Waiting for pods with selector $selector in namespace $namespace..."
    
    if kubectl wait --namespace "$namespace" \
        --for=condition=ready pod \
        --selector="$selector" \
        --timeout="${timeout}s"; then
        log "Pods with selector $selector are ready"
        return 0
    else
        log "ERROR: Pods with selector $selector failed to become ready within ${timeout}s"
        return 1
    fi
}

# Install NGINX Ingress Controller
install_nginx_ingress() {
    log "Installing NGINX Ingress Controller..."
    
    # Add Helm repository
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo update
    
    # Check if already installed
    if helm list -n ingress-nginx | grep -q ingress-nginx; then
        log "NGINX Ingress Controller already installed, upgrading..."
        helm upgrade ingress-nginx ingress-nginx/ingress-nginx \
            --namespace ingress-nginx \
            --reuse-values \
            --wait --timeout=300s
    else
        log "Installing NGINX Ingress Controller..."
        helm install ingress-nginx ingress-nginx/ingress-nginx \
            --namespace ingress-nginx \
            --create-namespace \
            --set controller.replicaCount=2 \
            --set controller.nodeSelector."kubernetes\.io/os"=linux \
            --set defaultBackend.nodeSelector."kubernetes\.io/os"=linux \
            --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"="/healthz" \
            --set controller.metrics.enabled=true \
            --set controller.podAnnotations."prometheus\.io/scrape"="true" \
            --set controller.podAnnotations."prometheus\.io/port"="10254" \
            --wait --timeout=300s
    fi
    
    # Wait for controller to be ready
    wait_for_pods "ingress-nginx" "app.kubernetes.io/component=controller" 300
    
    # Get external IP
    log "NGINX Ingress Controller external IP:"
    kubectl get service -n ingress-nginx ingress-nginx-controller \
        -o jsonpath='{.status.loadBalancer.ingress[0].ip}' || echo "IP pending..."
    
    log "NGINX Ingress Controller installation completed"
}

# Install cert-manager
install_cert_manager() {
    log "Installing cert-manager..."
    
    # Add Helm repository
    helm repo add jetstack https://charts.jetstack.io
    helm repo update
    
    # Check if already installed
    if helm list -n cert-manager | grep -q cert-manager; then
        log "cert-manager already installed, upgrading..."
        helm upgrade cert-manager jetstack/cert-manager \
            --namespace cert-manager \
            --reuse-values \
            --wait --timeout=300s
    else
        log "Installing cert-manager..."
        helm install cert-manager jetstack/cert-manager \
            --namespace cert-manager \
            --create-namespace \
            --version v1.13.0 \
            --set installCRDs=true \
            --set nodeSelector."kubernetes\.io/os"=linux \
            --wait --timeout=300s
    fi
    
    # Wait for cert-manager to be ready
    wait_for_pods "cert-manager" "app.kubernetes.io/name=cert-manager" 300
    
    log "cert-manager installation completed"
}

# Setup Cloudflare cluster issuer
setup_cloudflare_issuer() {
    if [[ -z "${CLOUDFLARE_API_KEY:-}" ]]; then
        log "WARNING: CLOUDFLARE_API_KEY not set, skipping Cloudflare issuer setup"
        return 0
    fi
    
    log "Setting up Cloudflare cluster issuer..."
    
    # Create Cloudflare API key secret
    kubectl create secret generic cloudflare-api-key \
        --from-literal=api-key="$CLOUDFLARE_API_KEY" \
        --namespace cert-manager \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Create ClusterIssuer
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
    
    log "Cloudflare cluster issuer configured"
}

# Verify installations
verify_installations() {
    log "Verifying installations..."
    
    # Check NGINX Ingress
    if kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller | grep -q Running; then
        log "NGINX Ingress Controller is running"
    else
        log "ERROR: NGINX Ingress Controller is not running"
        return 1
    fi
    
    # Check cert-manager
    if kubectl get pods -n cert-manager -l app.kubernetes.io/name=cert-manager | grep -q Running; then
        log "cert-manager is running"
    else
        log "ERROR: cert-manager is not running"
        return 1
    fi
    
    # Check ClusterIssuer if Cloudflare is configured
    if [[ -n "${CLOUDFLARE_API_KEY:-}" ]]; then
        if kubectl get clusterissuer cloudflare-issuer >/dev/null 2>&1; then
            log "Cloudflare ClusterIssuer is configured"
        else
            log "WARNING: Cloudflare ClusterIssuer is not configured"
        fi
    fi
    
    log "Installation verification completed"
}

# Main execution
main() {
    log "Starting cluster dependencies installation..."
    
    install_nginx_ingress
    install_cert_manager
    setup_cloudflare_issuer
    verify_installations
    
    log "Cluster dependencies installation completed successfully"
}

# Execute main function
main "$@"