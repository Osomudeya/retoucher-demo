#!/bin/bash

# Deploy Application (Optimized for Terraform-provisioned Jump Server)
# Deploys the retoucherirving application to AKS

set -euo pipefail

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check required environment variables
check_environment() {
    local required_vars=(
        "NAMESPACE"
        "ACR_LOGIN_SERVER"
        "BACKEND_IMAGE"
        "FRONTEND_IMAGE"
        "DATABASE_FQDN"
        "DATABASE_NAME"
        "DATABASE_USER"
        "DATABASE_PASSWORD"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log "ERROR: Environment variable $var is not set"
            exit 1
        fi
    done
    
    log "Environment variables validated"
}

# Verify jump server is ready (already configured by Terraform)
verify_jump_server_ready() {
    log "Verifying jump server readiness..."
    
    # Check if kubectl is working (should be ready from Terraform)
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log "ERROR: kubectl not connected to AKS cluster"
        log "Attempting to reconnect..."
        
        # Fallback: try to reconnect if needed
        if [[ -n "${ARM_CLIENT_ID:-}" ]]; then
            az login --service-principal \
                --username "$ARM_CLIENT_ID" \
                --password "$ARM_CLIENT_SECRET" \
                --tenant "$ARM_TENANT_ID" 2>/dev/null || true
            
            az aks get-credentials \
                --resource-group "${RESOURCE_GROUP_NAME}" \
                --name "${AKS_CLUSTER_NAME}" \
                --overwrite-existing 2>/dev/null || true
        fi
        
        if ! kubectl cluster-info >/dev/null 2>&1; then
            log "ERROR: Unable to connect to AKS cluster"
            exit 1
        fi
    fi
    
    log "Jump server is ready and connected to AKS"
}

# Create or update ACR secret for image pulling
create_acr_secret() {
    log "Creating/updating ACR secret for image pulling..."
    
    # Extract ACR name
    local acr_name=$(echo "$ACR_LOGIN_SERVER" | cut -d'.' -f1)
    
    # Get ACR credentials
    local acr_username=$(az acr credential show --name "$acr_name" --query username -o tsv 2>/dev/null)
    local acr_password=$(az acr credential show --name "$acr_name" --query passwords[0].value -o tsv 2>/dev/null)
    
    if [[ -z "$acr_username" ]] || [[ -z "$acr_password" ]]; then
        log "ERROR: Unable to get ACR credentials"
        exit 1
    fi
    
    # Create or update docker registry secret (idempotent)
    kubectl create secret docker-registry acr-secret \
        --namespace="$NAMESPACE" \
        --docker-server="$ACR_LOGIN_SERVER" \
        --docker-username="$acr_username" \
        --docker-password="$acr_password" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    log "ACR secret created/updated successfully"
}

# Create or update application secrets
create_app_secrets() {
    log "Creating/updating application secrets..."
    
    # Generate admin key if not provided (check if secret exists first)
    local admin_key="${ADMIN_KEY:-}"
    if [[ -z "$admin_key" ]]; then
        # Try to get existing admin key to maintain consistency
        admin_key=$(kubectl get secret app-secrets -n "$NAMESPACE" -o jsonpath='{.data.ADMIN_KEY}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
        if [[ -z "$admin_key" ]]; then
            admin_key=$(openssl rand -base64 32)
            log "Generated new admin key"
        else
            log "Using existing admin key"
        fi
    fi
    
    # Create or update application secrets (idempotent)
    kubectl create secret generic app-secrets \
        --namespace="$NAMESPACE" \
        --from-literal=DB_HOST="$DATABASE_FQDN" \
        --from-literal=DB_NAME="$DATABASE_NAME" \
        --from-literal=DB_USER="$DATABASE_USER" \
        --from-literal=DB_PASSWORD="$DATABASE_PASSWORD" \
        --from-literal=APPLICATIONINSIGHTS_CONNECTION_STRING="${APPLICATION_INSIGHTS_KEY:-}" \
        --from-literal=ADMIN_KEY="$admin_key" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    log "Application secrets created/updated successfully"
}

# Update Kubernetes manifests with current values
update_manifests() {
    log "Updating Kubernetes manifests..."
    
    # Create temporary directory for processed manifests
    local manifest_dir="k8s-processed"
    rm -rf "$manifest_dir"
    cp -r k8s "$manifest_dir"
    
    # Update backend deployment with specific image
    if [[ -f "$manifest_dir/backend-deployment.yaml" ]]; then
        # Replace placeholder or existing image
        sed -i "s|image: placeholder-image:latest|image: $BACKEND_IMAGE|g" "$manifest_dir/backend-deployment.yaml"
        sed -i "s|image: .*backend.*|image: $BACKEND_IMAGE|g" "$manifest_dir/backend-deployment.yaml"
        log "Updated backend image to: $BACKEND_IMAGE"
    fi
    
    # Update frontend deployment with specific image
    if [[ -f "$manifest_dir/frontend-deployment.yaml" ]]; then
        # Replace placeholder or existing image
        sed -i "s|image: placeholder-image:latest|image: $FRONTEND_IMAGE|g" "$manifest_dir/frontend-deployment.yaml"
        sed -i "s|image: .*frontend.*|image: $FRONTEND_IMAGE|g" "$manifest_dir/frontend-deployment.yaml"
        log "Updated frontend image to: $FRONTEND_IMAGE"
    fi
    
    # Update any template variables if they exist
    find "$manifest_dir" -name "*.yaml" -o -name "*.yml" | while read -r file; do
        if grep -q "{{.*}}" "$file" 2>/dev/null; then
            sed -i "s|{{IMAGE_TAG}}|${IMAGE_TAG:-latest}|g" "$file"
            sed -i "s|{{ACR_LOGIN_SERVER}}|$ACR_LOGIN_SERVER|g" "$file"
            sed -i "s|{{NAMESPACE}}|$NAMESPACE|g" "$file"
            sed -i "s|{{DATABASE_FQDN}}|$DATABASE_FQDN|g" "$file"
        fi
    done
    
    log "Kubernetes manifests updated successfully"
}

# Apply Kubernetes manifests in dependency order
apply_manifests() {
    log "Applying Kubernetes manifests..."
    
    local manifest_dir="k8s-processed"
    
    # Apply in specific order for dependencies
    local apply_order=(
        "namespace.yaml"
        "configmap.yaml" 
        "backend-deployment.yaml"
        "frontend-deployment.yaml"
        "backend-service.yaml"
        "frontend-service.yaml"
        "ingress.yaml"
    )
    
    # Apply manifests in order if they exist
    for manifest in "${apply_order[@]}"; do
        if [[ -f "$manifest_dir/$manifest" ]]; then
            log "Applying $manifest..."
            kubectl apply -f "$manifest_dir/$manifest"
        else
            log "Manifest $manifest not found, skipping..."
        fi
    done
    
    # Apply any remaining manifests not in the ordered list
    for manifest in "$manifest_dir"/*.yaml "$manifest_dir"/*.yml; do
        if [[ -f "$manifest" ]]; then
            local filename=$(basename "$manifest")
            if [[ ! " ${apply_order[*]} " =~ " ${filename} " ]]; then
                log "Applying additional manifest: $filename..."
                kubectl apply -f "$manifest"
            fi
        fi
    done
    
    log "All manifests applied successfully"
}

# Wait for deployments to be ready with better error reporting
wait_for_deployments() {
    log "Waiting for deployments to be ready..."
    
    local timeout=300
    local deployments=("backend" "frontend")
    
    for deployment in "${deployments[@]}"; do
        log "Waiting for deployment $deployment..."
        
        if kubectl rollout status deployment/"$deployment" \
            --namespace="$NAMESPACE" \
            --timeout="${timeout}s"; then
            log "Deployment $deployment is ready"
        else
            log "ERROR: Deployment $deployment failed to become ready"
            
            # Show debugging information
            log "Deployment status:"
            kubectl get deployment "$deployment" -n "$NAMESPACE" -o wide || true
            log "Pod status:"
            kubectl get pods -n "$NAMESPACE" -l app="$deployment" -o wide || true
            log "Recent events:"
            kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -10 || true
            
            return 1
        fi
    done
    
    log "All deployments are ready"
}

# Run database migrations with better error handling
run_database_migrations() {
    log "Running database migrations..."
    
    # Wait for backend pods to be ready
    if ! kubectl wait --for=condition=ready pod \
        -l app=backend \
        -n "$NAMESPACE" \
        --timeout=300s; then
        log "WARNING: Backend pods not ready, skipping migration"
        return 0
    fi
    
    # Get backend pod name
    local backend_pod=$(kubectl get pods -n "$NAMESPACE" -l app=backend -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [[ -n "$backend_pod" ]]; then
        log "Running migrations on pod: $backend_pod"
        
        # Check if migration command exists
        if kubectl exec -n "$NAMESPACE" "$backend_pod" -- npm list | grep -q "migrate" 2>/dev/null; then
            kubectl exec -n "$NAMESPACE" "$backend_pod" -- npm run db:migrate || {
                log "WARNING: Database migration failed"
                kubectl logs -n "$NAMESPACE" "$backend_pod" --tail=50 | grep -i error || true
            }
        else
            log "INFO: No migration script found, skipping database migration"
        fi
    else
        log "WARNING: No backend pod found for database migration"
    fi
}

# Show deployment status
show_deployment_status() {
    log "Current deployment status:"
    
    echo "Namespace: $NAMESPACE"
    echo "Deployments:"
    kubectl get deployments -n "$NAMESPACE" -o wide || true
    echo ""
    echo "Pods:"
    kubectl get pods -n "$NAMESPACE" -o wide || true
    echo ""
    echo "Services:"
    kubectl get services -n "$NAMESPACE" -o wide || true
    echo ""
    echo "Ingress:"
    kubectl get ingress -n "$NAMESPACE" -o wide || true
}

# Cleanup temporary files
cleanup() {
    log "Cleaning up temporary files..."
    rm -rf k8s-processed 2>/dev/null || true
}

# Main execution
main() {
    log "Starting application deployment..."
    log "Backend Image: $BACKEND_IMAGE"
    log "Frontend Image: $FRONTEND_IMAGE"
    log "Namespace: $NAMESPACE"
    
    # Set trap for cleanup
    trap cleanup EXIT
    
    check_environment
    verify_jump_server_ready
    create_acr_secret
    create_app_secrets
    update_manifests
    apply_manifests
    wait_for_deployments
    run_database_migrations
    show_deployment_status
    
    log "Application deployment completed successfully"
}

# Execute main function
main "$@"