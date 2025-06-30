#!/bin/bash

# destroy-local.sh - Complete local infrastructure destruction
# Run this from your project root directory

set -e

echo "RETOUCHER IRVING - LOCAL INFRASTRUCTURE DESTRUCTION"
echo "=================================================="

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() { echo -e "${BLUE}INFO: $1${NC}"; }
log_success() { echo -e "${GREEN}SUCCESS: $1${NC}"; }
log_warning() { echo -e "${YELLOW}WARNING: $1${NC}"; }
log_error() { echo -e "${RED}ERROR: $1${NC}"; }

# Check if we're in the right directory
if [ ! -d "terraform" ] || [ ! -f "terraform/main.tf" ]; then
    log_error "Please run this script from your project root directory (where terraform/ folder exists)"
    exit 1
fi

echo ""
log_warning "This script will PERMANENTLY DELETE all your infrastructure!"
log_warning "This includes:"
echo "  - AKS cluster and all workloads"
echo "  - Database and ALL data"
echo "  - Storage accounts and files"
echo "  - Container registry and images"
echo "  - DNS zones and configurations"
echo "  - Key vaults and secrets"
echo "  - Virtual networks and security rules"
echo "  - Jump server and access"
echo "  - Monitoring and log data"
echo ""
log_error "THIS ACTION CANNOT BE UNDONE!"
echo ""

read -p "Are you absolutely sure you want to destroy everything? Type 'yes' to confirm: " DESTROY_CONFIRM
if [[ ! $DESTROY_CONFIRM =~ ^[Yy][Ee][Ss]$ ]]; then
    log_info "Destruction cancelled"
    exit 0
fi

echo ""
log_info "Step 1: Prerequisites Check"
echo "----------------------------"

# Check Azure CLI
if ! command -v az &> /dev/null; then
    log_error "Azure CLI is not installed"
    exit 1
fi
log_success "Azure CLI found"

# Check Terraform
if ! command -v terraform &> /dev/null; then
    log_error "Terraform is not installed"
    exit 1
fi
log_success "Terraform found"

# Check Azure login
if ! az account show > /dev/null 2>&1; then
    log_warning "Not logged into Azure. Logging in now..."
    az login
else
    log_success "Already logged into Azure"
fi

echo ""
log_info "Step 2: Environment Setup"
echo "--------------------------"

# Get Azure account details
SUBSCRIPTION_ID=$(az account show --query "id" -o tsv)
TENANT_ID=$(az account show --query "tenantId" -o tsv)
ACCOUNT_NAME=$(az account show --query "user.name" -o tsv)

echo "Account: $ACCOUNT_NAME"
echo "Subscription: $SUBSCRIPTION_ID"
echo "Tenant: $TENANT_ID"

# Set up service principal
echo ""
log_info "Step 3: Service Principal Setup"
echo "--------------------------------"

# Check if we have the github-terraform service principal
SP_EXISTS=$(az ad sp list --display-name "github-terraform" --query "[0].appId" -o tsv 2>/dev/null || echo "")

if [ -n "$SP_EXISTS" ]; then
    log_success "Found existing github-terraform service principal"
    ARM_CLIENT_ID="$SP_EXISTS"
    
    # Reset the secret to get a new one
    log_info "Resetting client secret..."
    ARM_CLIENT_SECRET=$(az ad sp credential reset --id "$ARM_CLIENT_ID" --query "password" -o tsv)
    log_success "Service principal secret reset"
else
    log_error "github-terraform service principal not found"
    log_error "Cannot proceed with destruction without proper credentials"
    exit 1
fi

# Set all environment variables
echo ""
log_info "Step 4: Setting Environment Variables"
echo "-------------------------------------"

# Core Azure variables
export ARM_CLIENT_ID="$ARM_CLIENT_ID"
export ARM_CLIENT_SECRET="$ARM_CLIENT_SECRET"
export ARM_SUBSCRIPTION_ID="$SUBSCRIPTION_ID"
export ARM_TENANT_ID="$TENANT_ID"

# Terraform project variables
export TF_VAR_environment="production"
export TF_VAR_project_name="retoucherirving"
export TF_VAR_location="East US"
export TF_VAR_custom_domain="retoucherirving.com"

# Jump server automation
export TF_VAR_arm_client_id="$ARM_CLIENT_ID"
export TF_VAR_arm_client_secret="$ARM_CLIENT_SECRET"
export TF_VAR_arm_tenant_id="$TENANT_ID"

# Infrastructure configuration
export TF_VAR_database_admin_username="adminuser"
export TF_VAR_jump_server_admin_username="azureuser"
export TF_VAR_aks_node_count=2
export TF_VAR_aks_vm_size="Standard_D2s_v3"
export TF_VAR_create_role_assignments=true

# SSH key setup
if [ -f "$HOME/.ssh/retoucherirving_azure.pub" ]; then
    export TF_VAR_ssh_public_key="$(cat $HOME/.ssh/retoucherirving_azure.pub)"
    log_success "SSH public key loaded"
else
    log_warning "SSH key not found, using placeholder"
    export TF_VAR_ssh_public_key="ssh-rsa placeholder-key"
fi

# Database password (needed for destroy plan)
export TF_VAR_database_admin_password="placeholder-password"

# Terraform backend configuration
echo ""
log_info "Step 5: Terraform Backend Setup"
echo "--------------------------------"

# Use consistent naming
STATE_RG="rg-terraform-state-retoucher"
STATE_ACCOUNT="tfstateretoucher$(echo "$SUBSCRIPTION_ID" | tr -d '-' | cut -c1-8)"
STATE_CONTAINER="tfstate"
STATE_KEY="retoucherirving-production.tfstate"

log_info "Backend configuration:"
echo "  Resource Group: $STATE_RG"
echo "  Storage Account: $STATE_ACCOUNT"
echo "  Container: $STATE_CONTAINER"
echo "  State Key: $STATE_KEY"

# Check if backend exists
if ! az storage account show --name "$STATE_ACCOUNT" --resource-group "$STATE_RG" > /dev/null 2>&1; then
    log_error "Terraform state storage not found"
    log_error "Either infrastructure was never deployed or state storage was already deleted"
    exit 1
fi

echo ""
log_info "Step 6: Terraform Destroy Process"
echo "----------------------------------"

cd terraform

# Check if backend.conf exists
if [ ! -f "backend.conf" ]; then
    log_warning "backend.conf not found, creating temporary one..."
    cat > "backend.conf" << EOF
resource_group_name  = "$STATE_RG"
storage_account_name = "$STATE_ACCOUNT"
container_name       = "$STATE_CONTAINER"
key                 = "$STATE_KEY"
EOF
fi

# Initialize Terraform
log_info "Initializing Terraform..."
terraform init -backend-config="backend.conf"

log_success "Terraform initialized"

# Show current state
echo ""
log_info "Current infrastructure resources:"
terraform show -no-color | head -20 || log_warning "No resources found or state is empty"

# Create destroy plan
echo ""
log_info "Creating destruction plan..."
terraform plan -destroy \
    -var="ssh_public_key=$TF_VAR_ssh_public_key" \
    -var="database_admin_password=$TF_VAR_database_admin_password" \
    -out=destroy-plan

if [ $? -ne 0 ]; then
    log_error "Terraform destroy plan failed"
    exit 1
fi

log_success "Destruction plan created"

echo ""
echo "FINAL CONFIRMATION"
echo "=================="
echo ""
log_error "You are about to PERMANENTLY DELETE all infrastructure shown above!"
echo ""
read -p "Type 'DESTROY' in uppercase to confirm final destruction: " FINAL_CONFIRM

if [[ "$FINAL_CONFIRM" != "DESTROY" ]]; then
    log_info "Destruction cancelled - confirmation not received"
    rm -f destroy-plan
    exit 0
fi

echo ""
log_warning "Starting infrastructure destruction..."
terraform apply -auto-approve destroy-plan

if [ $? -eq 0 ]; then
    echo ""
    log_success "INFRASTRUCTURE DESTROYED SUCCESSFULLY!"
    
    # Optional: Clean up terraform state storage
    echo ""
    log_info "Terraform state cleanup options:"
    echo "1. Keep state storage (recommended for potential recovery)"
    echo "2. Delete state storage completely"
    echo ""
    read -p "Do you want to delete the Terraform state storage? (yes/no): " DELETE_STATE
    
    if [[ $DELETE_STATE =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Deleting Terraform state storage..."
        
        # Delete storage account
        az storage account delete \
            --name "$STATE_ACCOUNT" \
            --resource-group "$STATE_RG" \
            --yes
        
        # Delete resource group if empty
        REMAINING_RESOURCES=$(az resource list --resource-group "$STATE_RG" --query "length(@)" -o tsv)
        if [ "$REMAINING_RESOURCES" -eq "0" ]; then
            az group delete --name "$STATE_RG" --yes --no-wait
            log_success "State storage and resource group deleted"
        else
            log_warning "State resource group has other resources, not deleting"
        fi
    else
        log_info "State storage preserved at:"
        echo "  Resource Group: $STATE_RG"
        echo "  Storage Account: $STATE_ACCOUNT"
    fi
    
    # Optional: Clean up service principal
    echo ""
    read -p "Do you want to delete the service principal 'github-terraform'? (yes/no): " DELETE_SP
    
    if [[ $DELETE_SP =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Deleting service principal..."
        az ad sp delete --id "$ARM_CLIENT_ID"
        log_success "Service principal deleted"
    else
        log_info "Service principal preserved for future use"
    fi
    
    echo ""
    log_success "DESTRUCTION COMPLETED!"
    echo ""
    echo "Summary:"
    echo "- All infrastructure resources: DESTROYED"
    echo "- Domain DNS: May need manual cleanup"
    echo "- GitHub secrets: Still configured (manual cleanup recommended)"
    echo ""
    log_warning "Remember to:"
    echo "1. Update your domain DNS settings if needed"
    echo "2. Clean up GitHub repository secrets if no longer needed"
    echo "3. Check for any orphaned resources in Azure portal"
    
else
    log_error "Infrastructure destruction failed"
    log_error "Some resources may still exist - check Azure portal"
    exit 1
fi

cd ..

echo ""
log_success "Destruction script completed!"