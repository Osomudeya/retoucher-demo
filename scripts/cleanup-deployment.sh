#!/bin/bash

# Cleanup Deployment
# Removes application resources from AKS cluster

set -euo pipefail

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to confirm cleanup action
confirm_cleanup() {
    local namespace=${1:-$NAMESPACE}
    
    echo "WARNING: This will delete all resources in namespace '$namespace'"
    echo "This action cannot be undone."
    
    if [[ "${FORCE_CLEANUP:-false}" == "true" ]]; then
        log "Force cleanup enabled, proceeding without confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
}

# Function to cleanup application resources
cleanup_application() {
    local namespace=${1:-$NAMESPACE}
    
    log "Cleaning up application resources in namespace '$namespace'..."
    
    # Delete deployments
    if kubectl get deployments -n "$namespace" >/dev/null 2>&1; then
        log "Deleting deployments..."
        kubectl delete deployments --all -n "$namespace" --timeout=60s
    fi
    
    # Delete services
    if kubectl get services -n "$namespace" >/dev/null 2>&1; then
        log "Deleting services..."
        kubectl delete services --all -n "$namespace" --timeout=60s
    fi
    
    # Delete ingress
    if kubectl get ingress -n "$namespace" >/dev/null 2>&1; then
        log "Deleting ingress resources..."
        kubectl delete ingress --all -n "$namespace" --timeout=60s
    fi
    
    # Delete configmaps (except kube-root-ca.crt)
    if kubectl get configmaps -n "$namespace" >/dev/null 2>&1; then
        log "Deleting configmaps..."
        kubectl delete configmaps --all -n "$namespace" --ignore-not-found=true
    fi
    
    # Delete secrets (except default service account token)
    if kubectl get secrets -n "$namespace" >/dev/null 2>&1; then
        log "Deleting application secrets..."
        kubectl delete secret acr-secret app-secrets --ignore-not-found=true -n "$namespace"
    fi
    
    # Delete persistent volume claims
    if kubectl get pvc -n "$namespace" >/dev/null 2>&1; then
        log "Deleting persistent volume claims..."
        kubectl delete pvc --all -n "$namespace" --timeout=60s
    fi
    
    log "Application resources cleanup completed"
}

# Function to cleanup certificates
cleanup_certificates() {
    local namespace=${1:-$NAMESPACE}
    
    log "Cleaning up certificates in namespace '$namespace'..."
    
    if kubectl get certificates -n "$namespace" >/dev/null 2>&1; then
        kubectl delete certificates --all -n "$namespace" --timeout=60s
        log "Certificates deleted"
    else
        log "No certificates found to delete"
    fi
}

# Function to force delete stuck resources
force_cleanup_stuck_resources() {
    local namespace=${1:-$NAMESPACE}
    
    log "Checking for stuck resources in namespace '$namespace'..."
    
    # Force delete stuck pods
    local stuck_pods=$(kubectl get pods -n "$namespace" --field-selector=status.phase!=Running,status.phase!=Succeeded --no-headers 2>/dev/null | awk '{print $1}' || echo "")
    
    if [[ -n "$stuck_pods" ]]; then
        log "Force deleting stuck pods..."
        for pod in $stuck_pods; do
            kubectl delete pod "$pod" -n "$namespace" --force --grace-period=0 --ignore-not-found=true
        done
    fi
    
    # Check for finalizers that might prevent deletion
    local resources_with_finalizers=$(kubectl get all -n "$namespace" -o json 2>/dev/null | jq -r '.items[] | select(.metadata.finalizers | length > 0) | "\(.kind)/\(.metadata.name)"' 2>/dev/null || echo "")
    
    if [[ -n "$resources_with_finalizers" ]]; then
        log "WARNING: Found resources with finalizers that might prevent cleanup:"
        echo "$resources_with_finalizers"
    fi
}

# Function to cleanup namespace (optional)
cleanup_namespace() {
    local namespace=${1:-$NAMESPACE}
    local delete_namespace=${DELETE_NAMESPACE:-false}
    
    if [[ "$delete_namespace" == "true" ]]; then
        log "Deleting namespace '$namespace'..."
        kubectl delete namespace "$namespace" --timeout=120s
        log "Namespace '$namespace' deleted"
    else
        log "Namespace cleanup skipped (set DELETE_NAMESPACE=true to delete namespace)"
    fi
}

# Function to verify cleanup
verify_cleanup() {
    local namespace=${1:-$NAMESPACE}
    
    log "Verifying cleanup in namespace '$namespace'..."
    
    # Check remaining resources
    local remaining_pods=$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null | wc -l)
    local remaining_services=$(kubectl get services -n "$namespace" --no-headers 2>/dev/null | wc -l)
    local remaining_deployments=$(kubectl get deployments -n "$namespace" --no-headers 2>/dev/null | wc -l)
    local remaining_ingress=$(kubectl get ingress -n "$namespace" --no-headers 2>/dev/null | wc -l)
    
    log "Remaining resources:"
    log "  Pods: $remaining_pods"
    log "  Services: $remaining_services"
    log "  Deployments: $remaining_deployments"
    log "  Ingress: $remaining_ingress"
    
    if [[ "$remaining_pods" -eq "0" ]] && [[ "$remaining_services" -eq "0" ]] && [[ "$remaining_deployments" -eq "0" ]] && [[ "$remaining_ingress" -eq "0" ]]; then
        log "Cleanup verification: SUCCESS - All application resources removed"
        return 0
    else
        log "Cleanup verification: WARNING - Some resources may still exist"
        
        # Show remaining resources
        log "Remaining resources in namespace '$namespace':"
        kubectl get all -n "$namespace" 2>/dev/null || log "No resources found or namespace doesn't exist"
        return 1
    fi
}

# Main execution
main() {
    local namespace=${NAMESPACE:-retoucherirving}
    
    log "Starting cleanup for namespace: $namespace"
    
    # Check if namespace exists
    if ! kubectl get namespace "$namespace" >/dev/null 2>&1; then
        log "Namespace '$namespace' does not exist, nothing to cleanup"
        exit 0
    fi
    
    # Confirm cleanup action
    confirm_cleanup "$namespace"
    
    # Perform cleanup steps
    cleanup_certificates "$namespace"
    cleanup_application "$namespace"
    force_cleanup_stuck_resources "$namespace"
    
    # Wait a bit for resources to be fully deleted
    log "Waiting for resource deletion to complete..."
    sleep 10
    
    # Verify cleanup
    verify_cleanup "$namespace"
    
    # Optional namespace deletion
    cleanup_namespace "$namespace"
    
    log "Cleanup process completed"
}

# Show usage information
show_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Environment Variables:"
    echo "  NAMESPACE         - Kubernetes namespace to clean up (default: retoucherirving)"
    echo "  DELETE_NAMESPACE  - Set to 'true' to delete the namespace (default: false)"
    echo "  FORCE_CLEANUP     - Set to 'true' to skip confirmation (default: false)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Interactive cleanup"
    echo "  FORCE_CLEANUP=true $0                # Automatic cleanup"
    echo "  DELETE_NAMESPACE=true $0             # Cleanup and delete namespace"
    echo "  NAMESPACE=staging FORCE_CLEANUP=true $0  # Cleanup staging namespace"
}

# Handle command line arguments
case "${1:-}" in
    -h|--help)
        show_usage
        exit 0
        ;;
    *)
        # Execute main function
        main "$@"
        ;;
esac