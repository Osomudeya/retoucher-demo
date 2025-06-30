#!/bin/bash

# deploy-local.sh - Complete local infrastructure deployment
# Run this from your project root directory

set -e

echo "RETOUCHER IRVING - LOCAL INFRASTRUCTURE DEPLOYMENT"
echo "================================================="

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

# --------------------------------------------------
### Step 1: Prerequisites Check
# --------------------------------------------------

# Check if we're in the right directory
if [ ! -d "terraform" ] || [ ! -f "terraform/main.tf" ]; then
    log_error "Please run this script from your project root directory (where terraform/ folder exists)"
    exit 1
fi

echo ""
log_info "Step 1: Prerequisites Check"
echo "----------------------------"

# Check Azure CLI
if ! command -v az &> /dev/null; then
    log_error "Azure CLI is not installed. Please install it first:"
    echo "  curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"
    exit 1
fi
log_success "Azure CLI found"

# Check Terraform
if ! command -v terraform &> /dev/null; then
    log_error "Terraform is not installed. Please install it first:"
    echo "  https://learn.hashicorp.com/tutorials/terraform/install-cli"
    exit 1
fi
log_success "Terraform found"

# Check jq for JSON parsing
if ! command -v jq &> /dev/null; then
    log_warning "jq is not installed. Installing jq for JSON parsing..."
    sudo apt-get update && sudo apt-get install -y jq
fi
log_success "jq found"

# Check Azure login
if ! az account show > /dev/null 2>&1; then
    log_warning "Not logged into Azure. Logging in now..."
    az login
else
    log_success "Already logged into Azure"
fi

# --------------------------------------------------
### Step 2: Environment Setup
# --------------------------------------------------

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

# --------------------------------------------------
### Step 3: Service Principal Setup with Proper Permissions
# --------------------------------------------------

echo ""
log_info "Step 3: Service Principal Setup with Proper Permissions"
echo "--------------------------------------------------------"

# Check for existing credentials file
if [ -f "$HOME/azure-credentials.env" ]; then
    log_info "Found existing Azure credentials file..."
    source "$HOME/azure-credentials.env"
    
    # Test if existing credentials work
    if [ -n "$ARM_CLIENT_ID" ] && [ -n "$ARM_CLIENT_SECRET" ] && [ -n "$ARM_TENANT_ID" ]; then
        log_info "Testing existing service principal credentials..."
        if az login --service-principal \
            --username "$ARM_CLIENT_ID" \
            --password "$ARM_CLIENT_SECRET" \
            --tenant "$ARM_TENANT_ID" > /dev/null 2>&1; then
            log_success "Existing service principal credentials are valid"
            log_info "Using existing service principal: $ARM_CLIENT_ID"
            SKIP_SP_CREATION=true
        else
            log_warning "Existing credentials are invalid, will create new service principal"
            SKIP_SP_CREATION=false
        fi
    else
        log_warning "Credentials file incomplete, will create new service principal"
        SKIP_SP_CREATION=false
    fi
else
    log_info "No existing credentials found, will create new service principal"
    SKIP_SP_CREATION=false
fi

if [ "$SKIP_SP_CREATION" = false ]; then
    # Check if we already have a github-terraform service principal
    SP_EXISTS=$(az ad sp list --display-name "github-terraform" --query "[0].appId" -o tsv 2>/dev/null || echo "")

    if [ -n "$SP_EXISTS" ]; then
        log_success "Found existing github-terraform service principal"
        ARM_CLIENT_ID="$SP_EXISTS"
        
        # Check current permissions
        log_info "Checking current permissions..."
        CURRENT_ROLES=$(az role assignment list --assignee "$ARM_CLIENT_ID" --query "[].roleDefinitionName" -o tsv)
        
        if echo "$CURRENT_ROLES" | grep -q "Owner"; then
            log_success "Service principal has Owner permissions"
        elif echo "$CURRENT_ROLES" | grep -q "User Access Administrator"; then
            log_success "Service principal has User Access Administrator permissions"
        else
            log_warning "Service principal needs additional permissions for role assignments"
            log_info "Adding User Access Administrator role..."
            az role assignment create \
                --assignee "$ARM_CLIENT_ID" \
                --role "User Access Administrator" \
                --scope "/subscriptions/$SUBSCRIPTION_ID"
            log_success "User Access Administrator role added"
        fi
        
        # Reset the secret to get a new one
        log_info "Resetting client secret..."
        ARM_CLIENT_SECRET=$(az ad sp credential reset --id "$ARM_CLIENT_ID" --query "password" -o tsv)
        log_success "Service principal secret reset"
    else
        log_info "Creating new github-terraform service principal with proper permissions..."
        
        # Create service principal with Owner role (includes both Contributor + User Access Administrator)
        SP_OUTPUT=$(az ad sp create-for-rbac \
            --name "github-terraform" \
            --role "Owner" \
            --scopes "/subscriptions/$SUBSCRIPTION_ID")
        
        ARM_CLIENT_ID=$(echo "$SP_OUTPUT" | jq -r '.appId')
        ARM_CLIENT_SECRET=$(echo "$SP_OUTPUT" | jq -r '.password')
        log_success "Service principal created with Owner permissions"
    fi

    # Save credentials to file for future use
    log_info "Saving credentials to ~/azure-credentials.env for future use..."
    cat > "$HOME/azure-credentials.env" << EOF
# Azure Service Principal Credentials for Retoucher Irving
# Generated on $(date)
export ARM_CLIENT_ID="$ARM_CLIENT_ID"
export ARM_CLIENT_SECRET="$ARM_CLIENT_SECRET"
export ARM_SUBSCRIPTION_ID="$SUBSCRIPTION_ID"
export ARM_TENANT_ID="$TENANT_ID"

# Terraform Variables
export TF_VAR_environment="production"
export TF_VAR_project_name="retoucherirving"
export TF_VAR_location="East US"
export TF_VAR_custom_domain="retoucherirving.com"
export TF_VAR_arm_client_id="\$ARM_CLIENT_ID"
export TF_VAR_arm_client_secret="\$ARM_CLIENT_SECRET"
export TF_VAR_arm_tenant_id="\$ARM_TENANT_ID"
export TF_VAR_database_admin_username="adminuser"
export TF_VAR_jump_server_admin_username="azureuser"
export TF_VAR_aks_node_count=2
export TF_VAR_aks_vm_size="Standard_D2s_v3"
export TF_VAR_create_role_assignments=true
EOF
    chmod 600 "$HOME/azure-credentials.env"
    log_success "Credentials saved to ~/azure-credentials.env"
fi

# --------------------------------------------------
### Step 4: Setting Environment Variables
# --------------------------------------------------

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

# Jump server automation (same as ARM vars)
export TF_VAR_arm_client_id="$ARM_CLIENT_ID"
export TF_VAR_arm_client_secret="$ARM_CLIENT_SECRET"
export TF_VAR_arm_tenant_id="$TENANT_ID"

# Infrastructure configuration
export TF_VAR_database_admin_username="adminuser"
export TF_VAR_jump_server_admin_username="azureuser"
export TF_VAR_aks_node_count=2
export TF_VAR_aks_vm_size="Standard_D2s_v3"
export TF_VAR_create_role_assignments=true

# --------------------------------------------------
### Step 5: SSH Key Setup
# --------------------------------------------------

# SSH key setup
if [ -f "$HOME/.ssh/retoucherirving_azure.pub" ]; then
    export TF_VAR_ssh_public_key="$(cat $HOME/.ssh/retoucherirving_azure.pub)"
    log_success "SSH public key loaded from ~/.ssh/retoucherirving_azure.pub"
else
    log_warning "SSH key not found at ~/.ssh/retoucherirving_azure.pub"
    echo "Available SSH keys:"
    ls -la ~/.ssh/*.pub 2>/dev/null || echo "No SSH keys found"
    echo ""
    read -p "Enter path to your SSH public key: " SSH_KEY_PATH
    if [ -f "$SSH_KEY_PATH" ]; then
        export TF_VAR_ssh_public_key="$(cat $SSH_KEY_PATH)"
        log_success "SSH public key loaded from $SSH_KEY_PATH"
    else
        log_error "SSH key file not found: $SSH_KEY_PATH"
        exit 1
    fi
fi

# --------------------------------------------------
### Step 6: Database Password Setup
# --------------------------------------------------

# Database password
if [ -z "$TF_VAR_database_admin_password" ]; then
    read -s -p "Enter database admin password (or press Enter for auto-generated): " DB_PASSWORD
    echo ""
    if [ -z "$DB_PASSWORD" ]; then
        DB_PASSWORD="RetoucherDB$(date +%Y%m%d)!"
        log_info "Generated database password: $DB_PASSWORD"
    fi
    export TF_VAR_database_admin_password="$DB_PASSWORD"
fi

# --------------------------------------------------
### Step 7: Terraform Backend Setup
# --------------------------------------------------

echo ""
log_info "Step 7: Terraform Backend Setup"
echo "--------------------------------"

# Use consistent naming without date dependency
STATE_RG="rg-terraform-state-retoucher"
STATE_ACCOUNT="tfstateretoucher$(echo "$SUBSCRIPTION_ID" | tr -d '-' | cut -c1-8)"
STATE_CONTAINER="tfstate"
STATE_KEY="retoucherirving-production.tfstate"

log_info "Backend configuration:"
echo "  Resource Group: $STATE_RG"
echo "  Storage Account: $STATE_ACCOUNT"
echo "  Container: $STATE_CONTAINER"
echo "  State Key: $STATE_KEY"

# Create state storage if it doesn't exist
if ! az group show --name "$STATE_RG" > /dev/null 2>&1; then
    log_info "Creating Terraform state resource group..."
    az group create --name "$STATE_RG" --location "East US"
    log_success "Terraform state resource group created"
else
    log_success "Terraform state resource group already exists"
fi

if ! az storage account show --name "$STATE_ACCOUNT" --resource-group "$STATE_RG" > /dev/null 2>&1; then
    log_info "Creating Terraform state storage account..."
    az storage account create \
        --resource-group "$STATE_RG" \
        --name "$STATE_ACCOUNT" \
        --sku "Standard_LRS" \
        --encryption-services "blob"
    log_success "Terraform state storage account created"
else
    log_success "Terraform state storage account already exists"
fi

# Get storage account key
ACCOUNT_KEY=$(az storage account keys list --resource-group "$STATE_RG" --account-name "$STATE_ACCOUNT" --query '[0].value' -o tsv)

# Create container if it doesn't exist
if ! az storage container show --name "$STATE_CONTAINER" --account-name "$STATE_ACCOUNT" --account-key "$ACCOUNT_KEY" > /dev/null 2>&1; then
    log_info "Creating Terraform state container..."
    az storage container create --name "$STATE_CONTAINER" --account-name "$STATE_ACCOUNT" --account-key "$ACCOUNT_KEY"
    log_success "Terraform state container created"
else
    log_success "Terraform state container already exists"
fi

# UPDATE backend.conf file
log_info "Updating backend.conf file..."
BACKEND_CONF_FILE="terraform/backend.conf"

# Create or update backend.conf
cat > "$BACKEND_CONF_FILE" << EOF
# Terraform Backend Configuration
# Generated by deploy-local.sh on $(date)

resource_group_name  = "$STATE_RG"
storage_account_name = "$STATE_ACCOUNT"
container_name       = "$STATE_CONTAINER"
key                 = "$STATE_KEY"
EOF

log_success "backend.conf file updated"
echo "  File: $BACKEND_CONF_FILE"

# --------------------------------------------------
### Step 8: Terraform Init, Plan & Apply 
# --------------------------------------------------

echo ""
log_info "Step 8: Terraform Deployment"
echo "-----------------------------"

cd terraform

# Initialize Terraform using backend.conf file
log_info "Initializing Terraform with backend.conf..."
terraform init -backend-config="backend.conf" -reconfigure

log_success "Terraform initialized with persistent backend configuration"

# Validate configuration
log_info "Validating Terraform configuration..."
terraform validate
log_success "Terraform configuration valid"

# Format check
log_info "Formatting Terraform files..."
terraform fmt -recursive
log_success "Terraform files formatted"

# Plan
echo ""
log_info "Creating Terraform plan..."
terraform plan \
    -var="ssh_public_key=$TF_VAR_ssh_public_key" \
    -var="database_admin_password=$TF_VAR_database_admin_password" \
    -out=tfplan

if [ $? -ne 0 ]; then
    log_error "Terraform plan failed"
    exit 1
fi

log_success "Terraform plan created successfully"

# --------------------------------------------------
### Step 9: Apply Confirmation & Deployment
# --------------------------------------------------

echo ""
echo "DEPLOYMENT READY!"
echo "================"
echo ""
log_warning "Review the plan above carefully"
echo ""
read -p "Do you want to apply this plan? (yes/no): " APPLY_CONFIRM

if [[ $APPLY_CONFIRM =~ ^[Yy][Ee][Ss]$ ]]; then
    echo ""
    log_info "Applying Terraform plan..."
    terraform apply -auto-approve tfplan
    
    if [ $? -eq 0 ]; then
        echo ""
        log_success "INFRASTRUCTURE DEPLOYED SUCCESSFULLY!"
        echo ""
        echo "Getting deployment information..."
        
        # --------------------------------------------------
        ### Step 10: Output Infrastructure Details
        # --------------------------------------------------
        
        # Get outputs
        echo ""
        echo "INFRASTRUCTURE DETAILS:"
        echo "======================"
        echo "AKS Cluster: $(terraform output -raw aks_cluster_name 2>/dev/null || echo 'N/A')"
        echo "Resource Group: $(terraform output -raw aks_resource_group 2>/dev/null || echo 'N/A')"
        echo "ACR Login Server: $(terraform output -raw acr_login_server 2>/dev/null || echo 'N/A')"
        echo "Jump Server IP: $(terraform output -raw jump_server_public_ip 2>/dev/null || echo 'N/A')"
        echo "Ingress IP: $(terraform output -raw ingress_public_ip 2>/dev/null || echo 'N/A')"
        
        # DNS name servers
        echo ""
        echo "DNS CONFIGURATION:"
        echo "Configure these name servers in your domain registrar:"
        terraform output -json dns_zone_name_servers 2>/dev/null | jq -r '.[]' || echo "Run: terraform output dns_zone_name_servers"
        
        echo ""
        echo "ACCESS INFORMATION:"
        echo "Jump Server SSH: ssh -i ~/.ssh/retoucherirving_azure azureuser@$(terraform output -raw jump_server_public_ip 2>/dev/null || echo 'IP')"
        
        # --------------------------------------------------
        ### Step 11: GitHub Secrets Configuration Output
        # --------------------------------------------------
        
        echo ""
        echo "BACKEND CONFIGURATION (for GitHub Secrets):"
        echo "==========================================="
        echo "TF_STATE_RESOURCE_GROUP=$STATE_RG"
        echo "TF_STATE_STORAGE_ACCOUNT=$STATE_ACCOUNT"
        echo "TF_STATE_CONTAINER=$STATE_CONTAINER"
        echo "TF_STATE_KEY=$STATE_KEY"
        echo ""
        echo "AZURE CREDENTIALS (for GitHub Secrets):"
        echo "======================================="
        echo "ARM_CLIENT_ID=$ARM_CLIENT_ID"
        echo "ARM_CLIENT_SECRET=$ARM_CLIENT_SECRET"
        echo "ARM_TENANT_ID=$TENANT_ID"
        echo "ARM_SUBSCRIPTION_ID=$SUBSCRIPTION_ID"
        echo ""
        echo "AZURE_CREDENTIALS (JSON format for GitHub):"
        echo "==========================================="
        cat << EOF
{
  "clientId": "$ARM_CLIENT_ID",
  "clientSecret": "$ARM_CLIENT_SECRET",
  "subscriptionId": "$SUBSCRIPTION_ID",
  "tenantId": "$TENANT_ID"
}
EOF
        echo ""
        echo "SSH_PUBLIC_KEY (for GitHub Secrets):"
        echo "===================================="
        echo "$TF_VAR_ssh_public_key"
        echo ""
        echo "DATABASE_ADMIN_PASSWORD (for GitHub Secrets):"
        echo "============================================="
        echo "$TF_VAR_database_admin_password"
        echo ""
        log_success "Infrastructure is ready for application deployment!"
        log_success "backend.conf file updated with persistent backend configuration"
        
    else
        log_error "Terraform apply failed"
        exit 1
    fi
else
    log_info "Deployment cancelled by user"
    echo "To apply later, run: terraform apply tfplan"
fi

cd ..

# --------------------------------------------------
### Step 12: Completion Summary
# --------------------------------------------------

echo ""
log_success "Local deployment completed!"
echo ""
echo "Next steps:"
echo "1. Test jump server access: ssh -i ~/.ssh/retoucherirving_azure azureuser@\$(terraform -chdir=terraform output -raw jump_server_public_ip)"
echo "2. Update GitHub secrets with the values above"
echo "3. Push your code to GitHub for automated deployments (backend.conf is now updated)"
echo "4. Deploy your application using the app-deploy workflow"
echo ""
echo "Credentials saved to: ~/azure-credentials.env"
echo "For future deployments, you can run: source ~/azure-credentials.env && ./deploy-local.sh"