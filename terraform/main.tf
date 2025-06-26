# Configure Terraform and required providers
terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.85.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }

  # Store state in Azure Storage (configure backend separately)
  backend "azurerm" {

  }
}

# Configure Azure Provider
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  
  # ✅ ADD THIS LINE
  skip_provider_registration = true
}


# Generate random suffix for unique resource names
resource "random_id" "main" {
  byte_length = 4
}

locals {
  resource_suffix = random_id.main.hex
  common_tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
  }
}

# Create main resource group
resource "azurerm_resource_group" "main" {
  name     = "rg-${var.project_name}-${var.environment}-${local.resource_suffix}"
  location = var.location
  tags     = local.common_tags
}

# Hub-and-Spoke Networking Module
module "networking" {
  source = "./modules/networking"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  environment         = var.environment
  project_name        = var.project_name
  resource_suffix     = local.resource_suffix
  tags                = local.common_tags
}

# Jump Server Module
module "jump_server" {
  source = "./modules/jump-server"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  subnet_id           = module.networking.jump_server_subnet_id
  environment         = var.environment
  project_name        = var.project_name
  resource_suffix     = local.resource_suffix
  admin_username      = var.jump_server_admin_username
  ssh_public_key      = var.ssh_public_key
  tags                = local.common_tags
}

# Container Registry
resource "azurerm_container_registry" "main" {
  name                = "acr${var.project_name}${var.environment}${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Standard"
  admin_enabled       = true
  tags                = local.common_tags
}

# Private AKS Cluster Module
module "aks" {
  source = "./modules/aks"

  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  subnet_id                  = module.networking.aks_subnet_id
  environment                = var.environment
  project_name               = var.project_name
  resource_suffix            = local.resource_suffix
  node_count                 = var.aks_node_count
  vm_size                    = var.aks_vm_size
  container_registry_id      = azurerm_container_registry.main.id
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
  create_role_assignments    = var.create_role_assignments  # NEW
  tags                       = local.common_tags
}

# PostgreSQL Database Module
module "database" {
  source = "./modules/database"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  subnet_id           = module.networking.database_subnet_id
  vnet_id             = module.networking.spoke_vnet_id
  environment         = var.environment
  project_name        = var.project_name
  resource_suffix     = local.resource_suffix
  admin_username      = var.database_admin_username
  admin_password      = var.database_admin_password
  tags                = local.common_tags
}

# Monitoring Module (Azure Monitor, App Insights, Grafana)
module "monitoring" {
  source = "./modules/monitoring"

  resource_group_name     = azurerm_resource_group.main.name
  location                = azurerm_resource_group.main.location
  environment             = var.environment
  project_name            = var.project_name
  resource_suffix         = local.resource_suffix
  create_role_assignments = var.create_role_assignments  # NEW
  tags                    = local.common_tags
}

# Azure CDN Profile
resource "azurerm_cdn_profile" "main" {
  name                = "cdn-${var.project_name}-${var.environment}-${local.resource_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Standard_Microsoft"
  tags                = local.common_tags
}

# CDN Endpoint
resource "azurerm_cdn_endpoint" "main" {
  name                = "cdn-endpoint-${var.project_name}-${var.environment}-${local.resource_suffix}"
  profile_name        = azurerm_cdn_profile.main.name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  origin {
    name      = "primary"
    host_name = var.custom_domain
  }

  tags = local.common_tags
}