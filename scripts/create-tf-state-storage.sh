#!/bin/bash

# Create Terraform State Storage - Run this ONCE before any Terraform operations

set -e

echo "🏗️ Creating Terraform State Storage..."

# Check if logged into Azure
if ! az account show &> /dev/null; then
    echo "🔐 Please login to Azure first:"
    az login
fi

# Generate unique storage account name
STORAGE_ACCOUNT_NAME="tfstate$(date +%Y%m%d%H%M%S)"
RESOURCE_GROUP_NAME="rg-terraform-state"
LOCATION="East US"
CONTAINER_NAME="tfstate"

echo "📦 Creating storage account: $STORAGE_ACCOUNT_NAME"

# Create resource group
az group create \
    --name "$RESOURCE_GROUP_NAME" \
    --location "$LOCATION" \
    --output table

# Create storage account
az storage account create \
    --name "$STORAGE_ACCOUNT_NAME" \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --location "$LOCATION" \
    --sku "Standard_LRS" \
    --encryption-services blob \
    --output table

# Create container for state files
az storage container create \
    --name "$CONTAINER_NAME" \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --output table

# Get storage account key (needed for local development)
STORAGE_ACCOUNT_KEY=$(az storage account keys list \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --query '[0].value' -o tsv)

echo ""
echo "✅ Terraform state storage created successfully!"
echo "================================================"
echo "Resource Group:    $RESOURCE_GROUP_NAME"
echo "Storage Account:   $STORAGE_ACCOUNT_NAME"
echo "Container:         $CONTAINER_NAME"
echo "Location:          $LOCATION"
echo "================================================"

echo ""
echo "📋 Add these to your GitHub Secrets:"
echo "TF_STATE_RESOURCE_GROUP = $RESOURCE_GROUP_NAME"
echo "TF_STATE_STORAGE_ACCOUNT = $STORAGE_ACCOUNT_NAME"
echo "TF_STATE_CONTAINER = $CONTAINER_NAME"
echo "TF_STATE_KEY = terraform.tfstate"

echo ""
echo "💾 For local development, create terraform/backend.conf:"
echo "resource_group_name  = \"$RESOURCE_GROUP_NAME\""
echo "storage_account_name = \"$STORAGE_ACCOUNT_NAME\""
echo "container_name       = \"$CONTAINER_NAME\""
echo "key                  = \"terraform.tfstate\""

# Create backend.conf file for local use
cat > ../terraform/backend.conf << EOF
resource_group_name  = "$RESOURCE_GROUP_NAME"
storage_account_name = "$STORAGE_ACCOUNT_NAME"
container_name       = "$CONTAINER_NAME"
key                  = "terraform.tfstate"
EOF

echo "✅ Created terraform/backend.conf for local development"

echo ""
echo "🚀 Next steps:"
echo "1. Add the GitHub secrets shown above"
echo "2. For local development: terraform init -backend-config=backend.conf"
echo "3. The state file will be created automatically when you run terraform apply"