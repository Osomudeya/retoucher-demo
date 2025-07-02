#!/bin/bash

# get-github-secrets.sh - Enhanced script to gather all GitHub secrets
# Run this after successful terraform deployment

echo "🔐 RETOUCHER IRVING - GITHUB SECRETS GENERATOR"
echo "==============================================="

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }

# Check if logged into Azure
if ! az account show > /dev/null 2>&1; then
    echo "❌ Please login to Azure first: az login"
    exit 1
fi

# Get Azure account details
SUBSCRIPTION_ID=$(az account show --query "id" -o tsv)
TENANT_ID=$(az account show --query "tenantId" -o tsv)
ACCOUNT_NAME=$(az account show --query "user.name" -o tsv)

echo "Account: $ACCOUNT_NAME"
echo "Subscription: $SUBSCRIPTION_ID"
echo "Tenant: $TENANT_ID"
echo ""

# Try to get resource group from terraform output first
if [ -d "terraform" ] && [ -f "terraform/terraform.tfstate" ]; then
    cd terraform
    RESOURCE_GROUP=$(terraform output -raw aks_resource_group 2>/dev/null)
    cd ..
    if [ -n "$RESOURCE_GROUP" ] && [ "$RESOURCE_GROUP" != "null" ]; then
        log_success "Found resource group from Terraform: $RESOURCE_GROUP"
    else
        RESOURCE_GROUP=""
    fi
fi

# If not found, ask user
if [ -z "$RESOURCE_GROUP" ]; then
    echo "🔍 Finding your resources..."
    echo "Available resource groups:"
    az group list --query "[?starts_with(name, 'rg-retoucherirving')].name" -o table
    echo ""
    read -p "Enter your resource group name: " RESOURCE_GROUP
fi

echo ""
log_info "Gathering secrets from resource group: $RESOURCE_GROUP"
echo ""

# Initialize arrays for secrets
declare -A SECRETS

# Core Azure credentials
SECRETS["ARM_CLIENT_ID"]="${ARM_CLIENT_ID:-89f85e97-87b8-4338-ad6c-60ce33228f22}"
SECRETS["ARM_CLIENT_SECRET"]="${ARM_CLIENT_SECRET:-[SET_FROM_SERVICE_PRINCIPAL]}"
SECRETS["ARM_SUBSCRIPTION_ID"]="$SUBSCRIPTION_ID"
SECRETS["ARM_TENANT_ID"]="$TENANT_ID"

# Azure credentials JSON format
AZURE_CREDS="{\"clientId\":\"${SECRETS[ARM_CLIENT_ID]}\",\"clientSecret\":\"${ARM_CLIENT_SECRET:-[REPLACE]}\",\"subscriptionId\":\"$SUBSCRIPTION_ID\",\"tenantId\":\"$TENANT_ID\"}"
SECRETS["AZURE_CREDENTIALS"]="$AZURE_CREDS"

# Static secrets (user should set these)
SECRETS["SSH_PUBLIC_KEY"]="$(cat ~/.ssh/retoucherirving_azure.pub 2>/dev/null || echo '[ADD_YOUR_SSH_PUBLIC_KEY]')"
SECRETS["SSH_PRIVATE_KEY"]="$(cat ~/.ssh/retoucherirving_azure 2>/dev/null || echo '[ADD_YOUR_SSH_PRIVATE_KEY]')"
SECRETS["DATABASE_ADMIN_PASSWORD"]="[SET_STRONG_PASSWORD]"

# Terraform state (if created by deploy-local.sh)
SECRETS["TF_STATE_RESOURCE_GROUP"]="rg-terraform-state-retoucher"
SECRETS["TF_STATE_STORAGE_ACCOUNT"]="tfstateretoucher$(date +%Y%m%d)"
SECRETS["TF_STATE_CONTAINER"]="tfstate"
SECRETS["TF_STATE_KEY"]="retoucherirving-production.tfstate"

echo "🏗️ Azure Resources:"
echo "==================="

# Get ACR details
ACR_LOGIN_SERVER=$(az acr list --resource-group "$RESOURCE_GROUP" --query "[0].loginServer" -o tsv 2>/dev/null)
if [ -n "$ACR_LOGIN_SERVER" ]; then
    SECRETS["ACR_LOGIN_SERVER"]="$ACR_LOGIN_SERVER"
    
    # Get ACR credentials
    ACR_CREDS=$(az acr credential show --name "$(echo $ACR_LOGIN_SERVER | cut -d'.' -f1)" --query "{username:username, password:passwords[0].value}" -o json 2>/dev/null)
    if [ -n "$ACR_CREDS" ]; then
        SECRETS["ACR_USERNAME"]=$(echo "$ACR_CREDS" | jq -r '.username')
        SECRETS["ACR_PASSWORD"]=$(echo "$ACR_CREDS" | jq -r '.password')
    fi
    echo "✅ ACR: $ACR_LOGIN_SERVER"
else
    echo "❌ No ACR found"
fi

# Get AKS details
AKS_CLUSTER_NAME=$(az aks list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv 2>/dev/null)
if [ -n "$AKS_CLUSTER_NAME" ]; then
    SECRETS["AKS_CLUSTER_NAME"]="$AKS_CLUSTER_NAME"
    SECRETS["AKS_RESOURCE_GROUP"]="$RESOURCE_GROUP"
    echo "✅ AKS: $AKS_CLUSTER_NAME"
else
    echo "❌ No AKS cluster found"
fi

# Get Jump Server IP
JUMP_SERVER_IP=$(az vm list-ip-addresses --resource-group "$RESOURCE_GROUP" --query "[?contains(virtualMachine.name, 'jumphost')].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv 2>/dev/null)
if [ -n "$JUMP_SERVER_IP" ]; then
    SECRETS["JUMP_SERVER_IP"]="$JUMP_SERVER_IP"
    echo "✅ Jump Server: $JUMP_SERVER_IP"
else
    echo "❌ No jump server found"
fi

# Get Database details
DB_FQDN=$(az postgres flexible-server list --resource-group "$RESOURCE_GROUP" --query "[0].fullyQualifiedDomainName" -o tsv 2>/dev/null)
if [ -n "$DB_FQDN" ]; then
    SECRETS["DATABASE_HOST"]="$DB_FQDN"
    SECRETS["DATABASE_NAME"]="webapp"
    SECRETS["DATABASE_USER"]="adminuser"
    SECRETS["DATABASE_PASSWORD"]="[SAME_AS_DATABASE_ADMIN_PASSWORD]"
    echo "✅ Database: $DB_FQDN"
else
    echo "❌ No database found"
fi

# Get Application Insights
APP_INSIGHTS_KEY=$(az monitor app-insights component list --resource-group "$RESOURCE_GROUP" --query "[0].instrumentationKey" -o tsv 2>/dev/null)
if [ -n "$APP_INSIGHTS_KEY" ]; then
    SECRETS["APPLICATION_INSIGHTS_INSTRUMENTATION_KEY"]="$APP_INSIGHTS_KEY"
    SECRETS["APPINSIGHTS_INSTRUMENTATIONKEY"]="$APP_INSIGHTS_KEY"
    echo "✅ App Insights: $APP_INSIGHTS_KEY"
else
    echo "❌ No Application Insights found"
fi

# Security scanning (if configured)
SECRETS["SNYK_TOKEN"]="[SET_IF_USING_SNYK]"
SECRETS["SONAR_TOKEN"]="[SET_IF_USING_SONARCLOUD]"
SECRETS["SONAR_ORGANIZATION"]="[YOUR_SONAR_ORG]"
SECRETS["SONAR_PROJECT_KEY"]="[YOUR_SONAR_PROJECT_KEY]"

# CDN/DNS (if using Cloudflare)
SECRETS["CLOUDFLARE_API_KEY"]="[SET_IF_USING_CLOUDFLARE]"
SECRETS["CLOUDFLARE_EMAIL"]="[SET_IF_USING_CLOUDFLARE]"

echo ""
echo "📋 GITHUB SECRETS TO ADD/UPDATE"
echo "================================"

# Output all secrets in a format ready for GitHub
for key in $(printf '%s\n' "${!SECRETS[@]}" | sort); do
    echo "$key=${SECRETS[$key]}"
done

echo ""
echo "🔧 QUICK SETUP COMMANDS"
echo "======================="
echo ""
echo "# 1. Set up service principal secret (if needed):"
echo "ARM_CLIENT_SECRET=\$(az ad sp credential reset --id ${SECRETS[ARM_CLIENT_ID]} --query password --output tsv)"
echo ""
echo "# 2. Copy secrets to clipboard (macOS):"
echo "echo 'ARM_CLIENT_ID=${SECRETS[ARM_CLIENT_ID]}' | pbcopy"
echo ""
echo "# 3. Test service principal:"
echo "az login --service-principal --username ${SECRETS[ARM_CLIENT_ID]} --password \$ARM_CLIENT_SECRET --tenant ${SECRETS[ARM_TENANT_ID]}"

echo ""
echo "💡 IMPORTANT NOTES:"
echo "==================="
echo "1. Replace [SET_*] placeholders with actual values"
echo "2. Generate strong DATABASE_ADMIN_PASSWORD"
echo "3. Add SSH keys from your ~/.ssh/ directory"
echo "4. Configure SNYK/SONAR tokens if using security scanning"
echo "5. Set CLOUDFLARE credentials if using custom DNS"

echo ""
log_success "Secret gathering completed!"
echo ""
echo "📋 Next steps:"
echo "1. Go to GitHub → Repository → Settings → Secrets and variables → Actions"
echo "2. Add/update each secret from the list above"
echo "3. Test GitHub Actions workflow"
echo "4. Deploy your application"