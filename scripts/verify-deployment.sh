#!/bin/bash

# Verify Deployment
# Verifies that the application deployment was successful

set -euo pipefail

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check if a deployment is ready
check_deployment_status() {
    local deployment=$1
    local namespace=${2:-$NAMESPACE}
    
    local ready_replicas=$(kubectl get deployment "$deployment" -n "$namespace" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    local replicas=$(kubectl get deployment "$deployment" -n "$namespace" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    
    if [[ "$ready_replicas" == "$replicas" ]] && [[ "$replicas" != "0" ]]; then
        return 0
    else
        return 1
    fi
}

# Function to check pod health
check_pod_health() {
    local namespace=${1:-$NAMESPACE}
    
    log "Checking pod health in namespace $namespace..."
    
    # Get all pods
    local total_pods=$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null | wc -l)
    local running_pods=$(kubectl get pods -n "$namespace" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    local ready_pods=$(kubectl get pods -n "$namespace" -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null | grep -c "True" || echo "0")
    
    log "Pod status: $ready_pods/$running_pods/$total_pods (ready/running/total)"
    
    # Display pod details
    kubectl get pods -n "$namespace" -o wide
    
    if [[ "$ready_pods" == "$total_pods" ]] && [[ "$total_pods" -gt "0" ]]; then
        log "All pods are ready and healthy"
        return 0
    else
        log "WARNING: Not all pods are ready"
        return 1
    fi
}

# Function to check service endpoints
check_service_endpoints() {
    local namespace=${1:-$NAMESPACE}
    
    log "Checking service endpoints in namespace $namespace..."
    
    # Get services
    kubectl get services -n "$namespace"
    
    # Check if services have endpoints
    local services=$(kubectl get services -n "$namespace" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    
    for service in $services; do
        if [[ "$service" != "kubernetes" ]]; then
            local endpoints=$(kubectl get endpoints "$service" -n "$namespace" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w)
            if [[ "$endpoints" -gt "0" ]]; then
                log "Service $service has $endpoints endpoint(s)"
            else
                log "WARNING: Service $service has no endpoints"
            fi
        fi
    done
}

# Function to check ingress status
check_ingress_status() {
    local namespace=${1:-$NAMESPACE}
    
    log "Checking ingress status in namespace $namespace..."
    
    local ingresses=$(kubectl get ingress -n "$namespace" --no-headers 2>/dev/null | wc -l)
    
    if [[ "$ingresses" -gt "0" ]]; then
        kubectl get ingress -n "$namespace" -o wide
        
        # Check for external IP
        local external_ip=$(kubectl get ingress -n "$namespace" -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        
        if [[ -n "$external_ip" ]] && [[ "$external_ip" != "null" ]]; then
            log "Ingress external IP: $external_ip"
        else
            log "WARNING: Ingress external IP is pending"
        fi
    else
        log "No ingress resources found"
    fi
}

# Function to test application health endpoints
test_application_health() {
    local namespace=${1:-$NAMESPACE}
    
    log "Testing application health endpoints..."
    
    # Find backend pods
    local backend_pods=$(kubectl get pods -n "$namespace" -l app=backend -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    
    for pod in $backend_pods; do
        log "Testing health endpoint on pod $pod..."
        
        # Test health endpoint
        if kubectl exec -n "$namespace" "$pod" -- curl -f http://localhost:3001/health >/dev/null 2>&1; then
            log "Health endpoint on $pod is responding"
        else
            log "WARNING: Health endpoint on $pod is not responding"
        fi
    done
    
    # Find frontend pods
    local frontend_pods=$(kubectl get pods -n "$namespace" -l app=frontend -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    
    for pod in $frontend_pods; do
        log "Testing frontend pod $pod..."
        
        # Simple connectivity test (assuming nginx or similar)
        if kubectl exec -n "$namespace" "$pod" -- wget -q -O /dev/null http://localhost:80 2>/dev/null; then
            log "Frontend pod $pod is responding"
        else
            log "WARNING: Frontend pod $pod is not responding"
        fi
    done
}

# Function to check certificates (if using cert-manager)
check_certificates() {
    local namespace=${1:-$NAMESPACE}
    
    log "Checking SSL certificates..."
    
    local certificates=$(kubectl get certificates -n "$namespace" --no-headers 2>/dev/null | wc -l)
    
    if [[ "$certificates" -gt "0" ]]; then
        kubectl get certificates -n "$namespace"
        
        # Check certificate status
        local ready_certs=$(kubectl get certificates -n "$namespace" -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -c "True" || echo "0")
        
        if [[ "$ready_certs" == "$certificates" ]]; then
            log "All certificates are ready"
        else
            log "WARNING: Not all certificates are ready"
        fi
    else
        log "No certificates found"
    fi
}

# Function to display resource usage
show_resource_usage() {
    local namespace=${1:-$NAMESPACE}
    
    log "Resource usage in namespace $namespace:"
    
    # Get resource usage if metrics are available
    if kubectl top pods -n "$namespace" >/dev/null 2>&1; then
        kubectl top pods -n "$namespace"
    else
        log "Metrics not available (metrics-server not installed)"
    fi
}

# Function to display deployment summary
display_summary() {
    local namespace=${1:-$NAMESPACE}
    
    log "Deployment Summary:"
    log "==================="
    
    # Count resources
    local pods=$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null | wc -l)
    local running_pods=$(kubectl get pods -n "$namespace" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    local services=$(kubectl get services -n "$namespace" --no-headers 2>/dev/null | wc -l)
    local ingresses=$(kubectl get ingress -n "$namespace" --no-headers 2>/dev/null | wc -l)
    local deployments=$(kubectl get deployments -n "$namespace" --no-headers 2>/dev/null | wc -l)
    
    log "Namespace: $namespace"
    log "Deployments: $deployments"
    log "Pods: $running_pods/$pods (running/total)"
    log "Services: $services"
    log "Ingresses: $ingresses"
    
    # Check overall health
    if check_deployment_status "backend" "$namespace" && check_deployment_status "frontend" "$namespace"; then
        log "Overall Status: HEALTHY"
        return 0
    else
        log "Overall Status: DEGRADED"
        return 1
    fi
}

# Main execution
main() {
    local namespace=${NAMESPACE:-retoucherirving}
    
    log "Starting deployment verification for namespace: $namespace"
    
    # Verify namespace exists
    if ! kubectl get namespace "$namespace" >/dev/null 2>&1; then
        log "ERROR: Namespace $namespace does not exist"
        exit 1
    fi
    
    # Run all checks
    check_pod_health "$namespace"
    check_service_endpoints "$namespace"
    check_ingress_status "$namespace"
    test_application_health "$namespace"
    check_certificates "$namespace"
    show_resource_usage "$namespace"
    
    # Display final summary
    if display_summary "$namespace"; then
        log "Deployment verification completed successfully"
        exit 0
    else
        log "Deployment verification completed with warnings"
        exit 1
    fi
}

# Execute main function
main "$@"