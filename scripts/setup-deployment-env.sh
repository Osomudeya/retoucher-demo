#!/bin/bash

# Setup Deployment Environment (Simplified for Terraform-provisioned Jump Server)
# Minimal setup since Terraform already configured most tools

set -euo pipefail

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Verify required environment variables
check_environment() {
    local required_vars=(
        "NAMESPACE"
        "ACR_LOGIN_SERVER"
    )
    
    # Optional vars for fallback authentication
    local optional_vars=(
        "RESOURCE_GROUP_NAME"
        "AKS_CLUSTER_NAME"
        "ARM_CLIENT_ID"
        "ARM_CLIENT_SECRET" 
        "ARM_TENANT_ID"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log "ERROR: Environment variable $var is not set"
            exit 1
        fi
    done
    
    log "Required environment variables validated"
    
    # Log optional variables for debugging
    for var in "${optional_vars[@]}"; do
        if [[ -n "${!var:-}" ]]; then
            log "Optional variable $var is set"
        else
            log "Optional variable $var is not set"
        fi
    done
}

# Verify tools are installed (should be done by Terraform)
verify_tools() {
    log "Verifying required tools are installed..."
    
    local tools=("kubectl" "az" "helm" "docker")
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            local version=$($tool --version 2>/dev/null | head -n1 || echo "version unknown")
            log "Found $tool: $version"
        else
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log "ERROR: Missing tools: ${missing_tools[*]}"
        log "These should have been installed by Terraform provisioning"
        exit 1
    fi
    
    log "All required tools are available"
}

# Verify AKS connectivity (should be configured by Terraform)
verify_aks_connectivity() {
    log "Verifying AKS cluster connectivity..."
    
    # Test basic connectivity
    if kubectl cluster-info >/dev/null 2>&1; then
        log "AKS cluster connectivity verified"
        
        # Show cluster info
        local cluster_info=$(kubectl cluster-info 2>/dev/null | head -n2 || echo "Cluster info unavailable")
        log "Cluster info: $cluster_info"
        
        # Show node count
        local node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "0")
        log "Cluster nodes: $node_count"
        
        return 0
    else
        log "WARNING: AKS cluster not accessible, attempting to reconnect..."
        return 1
    fi
}

# Reconnect to AKS if needed (fallback)
reconnect_aks() {
    log "Attempting to reconnect to AKS cluster..."
    
    # Check if we have the required variables for reconnection
    if [[ -z "${ARM_CLIENT_ID:-}" ]] || [[ -z "${ARM_CLIENT_SECRET:-}" ]] || [[ -z "${ARM_TENANT_ID:-}" ]]; then
        log "ERROR: Missing Azure authentication variables for reconnection"
        exit 1
    fi
    
    if [[ -z "${RESOURCE_GROUP_NAME:-}" ]] || [[ -z "${AKS_CLUSTER_NAME:-}" ]]; then
        log "ERROR: Missing AKS cluster information for reconnection"
        exit 1
    fi
    
    # Login to Azure
    log "Logging into Azure..."
    if az login --service-principal \
        --username "$ARM_CLIENT_ID" \
        --password "$ARM_CLIENT_SECRET" \
        --tenant "$ARM_TENANT_ID" \
        --output none 2>/dev/null; then
        log "Azure login successful"
    else
        log "ERROR: Azure login failed"
        exit 1
    fi
    
    # Get AKS credentials
    log "Getting AKS credentials..."
    if az aks get-credentials \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --name "$AKS_CLUSTER_NAME" \
        --overwrite-existing \
        --output none 2>/dev/null; then
        log "AKS credentials updated"
    else
        log "ERROR: Failed to get AKS credentials"
        exit 1
    fi
    
    # Verify connectivity again
    if kubectl cluster-info >/dev/null 2>&1; then
        log "AKS connectivity restored"
    else
        log "ERROR: Still unable to connect to AKS cluster"
        exit 1
    fi
}

# Verify ACR access
verify_acr_access() {
    log "Verifying ACR access..."
    
    # Extract ACR name from login server
    local acr_name=$(echo "$ACR_LOGIN_SERVER" | cut -d'.' -f1)
    
    # Test ACR access
    if az acr show --name "$acr_name" >/dev/null 2>&1; then
        log "ACR access verified for: $acr_name"
        
        # Login to ACR (may be needed for some operations)
        if az acr login --name "$acr_name" --output none 2>/dev/null; then
            log "ACR login successful"
        else
            log "WARNING: ACR login failed, but ACR is accessible"
        fi
    else
        log "ERROR: Unable to access ACR: $acr_name"
        exit 1
    fi
}

# Verify/create namespace
setup_namespace() {
    local namespace="${NAMESPACE}"
    
    log "Setting up namespace: $namespace"
    
    # Check if namespace exists
    if kubectl get namespace "$namespace" >/dev/null 2>&1; then
        log "Namespace $namespace already exists"
    else
        log "Creating namespace: $namespace"
        if kubectl create namespace "$namespace"; then
            log "Namespace $namespace created successfully"
        else
            log "ERROR: Failed to create namespace $namespace"
            exit 1
        fi
    fi
    
    # Verify namespace is active
    if kubectl get namespace "$namespace" -o jsonpath='{.status.phase}' | grep -q "Active"; then
        log "Namespace $namespace is active and ready"
    else
        log "WARNING: Namespace $namespace may not be ready"
    fi
}

# Show environment summary
show_environment_summary() {
    log "Environment Summary:"
    log "==================="
    log "Namespace: ${NAMESPACE}"
    log "ACR Server: ${ACR_LOGIN_SERVER}"
    log "Resource Group: ${RESOURCE_GROUP_NAME:-not-set}"
    log "AKS Cluster: ${AKS_CLUSTER_NAME:-not-set}"
    
    # Show cluster status
    local node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "0")
    local namespace_count=$(kubectl get namespaces --no-headers 2>/dev/null | wc -l || echo "0")
    
    log "Cluster nodes: $node_count"
    log "Total namespaces: $namespace_count"
    log "Environment setup: READY"
}

# Main execution
main() {
    log "Starting deployment environment verification..."
    log "Note: Most setup should already be done by Terraform provisioning"
    
    check_environment
    verify_tools
    
    # Try to verify AKS connectivity, reconnect if needed
    if ! verify_aks_connectivity; then
        reconnect_aks
    fi
    
    verify_acr_access
    setup_namespace
    show_environment_summary
    
    log "Deployment environment setup completed successfully"
}

# Execute main function
main "$@"