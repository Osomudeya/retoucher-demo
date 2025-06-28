## =============================================================================
## TERRAFORM CONFIGURATION
## =============================================================================

terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.34.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }

  backend "azurerm" {}
}

provider "azurerm" {
  features {}
}

## =============================================================================
## LOCALS AND RANDOM SUFFIX
## =============================================================================

# Generate random suffix for unique resource names across deployments
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

## =============================================================================
## RESOURCE GROUPS
## =============================================================================

# Main resource group for core infrastructure components
resource "azurerm_resource_group" "main" {
  name     = "rg-${var.project_name}-${var.environment}-${local.resource_suffix}"
  location = var.location
  tags     = local.common_tags
}

# Separate resource group for DNS zone management
resource "azurerm_resource_group" "dns" {
  name     = "rg-dns-${var.project_name}-${var.environment}-${local.resource_suffix}"
  location = var.location
  tags     = local.common_tags
}

## =============================================================================
## NETWORKING - HUB AND SPOKE ARCHITECTURE
## =============================================================================

# Hub-and-Spoke networking with VNet peering
# Hub VNet: Contains jump server for secure access
# Spoke VNet: Contains AKS cluster, database, and application workloads
module "networking" {
  source = "./modules/networking"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  environment         = var.environment
  project_name        = var.project_name
  resource_suffix     = local.resource_suffix
  tags                = local.common_tags
}

## =============================================================================
## CONTAINER REGISTRY
## =============================================================================

# Azure Container Registry for storing application Docker images
resource "azurerm_container_registry" "main" {
  name                = "acr${var.project_name}${var.environment}${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Standard"
  admin_enabled       = true
  tags                = local.common_tags
}

## =============================================================================
## MONITORING AND OBSERVABILITY
## =============================================================================

# Azure Monitor, Application Insights, and Log Analytics workspace
module "monitoring" {
  source = "./modules/monitoring"

  resource_group_name     = azurerm_resource_group.main.name
  location                = azurerm_resource_group.main.location
  environment             = var.environment
  project_name            = var.project_name
  resource_suffix         = local.resource_suffix
  create_role_assignments = var.create_role_assignments
  tags                    = local.common_tags
}

## =============================================================================
## KUBERNETES CLUSTER (AKS)
## =============================================================================

# Private AKS cluster deployed in spoke VNet
# Uses system-assigned managed identity for secure access to other Azure services
module "aks" {
  source = "./modules/aks"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  environment         = var.environment
  project_name        = var.project_name
  resource_suffix     = local.resource_suffix

  # Networking configuration
  aks_subnet_id = module.networking.aks_subnet_id

  # AKS cluster configuration
  node_count                 = var.aks_node_count
  vm_size                    = var.aks_vm_size
  container_registry_id      = azurerm_container_registry.main.id
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
  create_role_assignments    = var.create_role_assignments

  tags = local.common_tags

  depends_on = [
    module.networking,
    azurerm_container_registry.main
  ]
}

## =============================================================================
## PRIVATE DNS ZONE LINKING (Hub-to-Spoke DNS Resolution)
## =============================================================================

# Wait for AKS private DNS zone to be fully created before attempting to link it
resource "time_sleep" "wait_for_aks_dns_zone" {
  depends_on      = [module.aks]
  create_duration = "120s" # 2 minutes wait for DNS zone readiness
}

# Data source to find the private DNS zone automatically created by AKS
# This zone enables private endpoint resolution for the AKS API server
data "azurerm_private_dns_zone" "aks_zone" {
  name                = "privatelink.${module.aks.location}.azmk8s.io"
  resource_group_name = module.aks.node_resource_group

  depends_on = [
    module.aks,
    time_sleep.wait_for_aks_dns_zone
  ]
}

# Link Hub VNet to AKS private DNS zone
# This allows jump server in hub VNet to resolve private AKS API server endpoint
resource "azurerm_private_dns_zone_virtual_network_link" "hub_to_aks_dns" {
  name                  = "hub-to-aks-dns-${var.project_name}-${var.environment}"
  resource_group_name   = module.aks.node_resource_group
  private_dns_zone_name = data.azurerm_private_dns_zone.aks_zone.name
  virtual_network_id    = module.networking.hub_vnet_id
  registration_enabled  = false

  tags = merge(local.common_tags, {
    Purpose = "DNS resolution for jump server to AKS"
  })

  depends_on = [
    module.aks,
    data.azurerm_private_dns_zone.aks_zone,
    time_sleep.wait_for_aks_dns_zone
  ]
}

## =============================================================================
## JUMP SERVER (Bastion Host)
## =============================================================================

# Jump server for secure access to private AKS cluster
# Deployed in hub VNet with public IP for SSH access
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

  depends_on = [
    module.networking,
    module.aks
  ]
}

## =============================================================================
## PUBLIC NETWORKING AND DNS
## =============================================================================

# Static public IP for ingress controller (NGINX)
# Must be created in AKS node resource group for load balancer integration
resource "azurerm_public_ip" "ingress_ip" {
  name                = "${module.aks.cluster_name}-ingress-ip"
  resource_group_name = module.aks.node_resource_group # IMPORTANT: Must be in node RG
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard" # Required for AKS LoadBalancer service

  tags = merge(local.common_tags, {
    purpose = "AKS Ingress LoadBalancer"
  })

  depends_on = [module.aks]
}

# Public DNS zone for domain management
resource "azurerm_dns_zone" "domain" {
  name                = "retoucherirving.com"
  resource_group_name = azurerm_resource_group.dns.name
  tags                = local.common_tags
}

# DNS A record for root domain (retoucherirving.com)
resource "azurerm_dns_a_record" "domain_root" {
  name                = "@"
  zone_name           = azurerm_dns_zone.domain.name
  resource_group_name = azurerm_resource_group.dns.name
  ttl                 = 300
  records             = [azurerm_public_ip.ingress_ip.ip_address]
  tags                = local.common_tags
}

# DNS A record for www subdomain (www.retoucherirving.com)
resource "azurerm_dns_a_record" "www" {
  name                = "www"
  zone_name           = azurerm_dns_zone.domain.name
  resource_group_name = azurerm_resource_group.dns.name
  ttl                 = 300
  records             = [azurerm_public_ip.ingress_ip.ip_address]
  tags                = local.common_tags
}

## =============================================================================
## DATABASE
## =============================================================================

# PostgreSQL Flexible Server for application data storage
# Deployed in spoke VNet with private endpoint for security
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

## =============================================================================
## CONTENT DELIVERY NETWORK (CDN)
## =============================================================================

# Azure CDN for global content delivery and caching
resource "azurerm_cdn_profile" "main" {
  name                = "cdn-${var.project_name}-${var.environment}-${local.resource_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Standard_Microsoft"
  tags                = local.common_tags
}

# CDN endpoint pointing to custom domain
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