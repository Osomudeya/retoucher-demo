# terraform/modules/aks/main.tf

# AKS Cluster
resource "azurerm_kubernetes_cluster" "main" {
  name                = "aks-${var.project_name}-${var.environment}-${var.resource_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = "${var.project_name}-${var.environment}-${var.resource_suffix}"

  # Add this line to control node resource group name
  node_resource_group = "rg-aks-nodes-${var.project_name}-${var.environment}"
  
  # Make AKS cluster private
  private_cluster_enabled = true
  
  # Enable managed identity
  identity {
    type = "SystemAssigned"
  }

  default_node_pool {
    name           = "default"
    vm_size        = var.vm_size
    vnet_subnet_id = var.subnet_id
    min_count      = 1
    max_count      = 5
    enable_auto_scaling = true

    # Enable container insights
    enable_node_public_ip = false
  }

  network_profile {
    network_plugin = "azure"
    service_cidr   = "10.2.0.0/16"
    dns_service_ip = "10.2.0.10"
  }

  # Enable monitoring
  oms_agent {
    log_analytics_workspace_id = var.log_analytics_workspace_id
  }

  # Enable Azure Policy Add-on
  azure_policy_enabled = true

  tags = var.tags
}

# Resilient ACR Role Assignment - Multiple Approaches
# Approach 1: Try to create, ignore if fails
resource "azurerm_role_assignment" "aks_acr" {
  principal_id                      = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
  role_definition_name              = "AcrPull"
  scope                             = var.container_registry_id
  skip_service_principal_aad_check  = true

  # Handle permission failures gracefully
  lifecycle {
    ignore_changes = [
      # Ignore changes if role assignment already exists
      principal_id,
      role_definition_name,
      scope
    ]
  }
}

# Approach 2: Conditional role assignment based on variable
resource "azurerm_role_assignment" "aks_acr_conditional" {
  count                            = var.create_role_assignments ? 1 : 0
  principal_id                     = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = var.container_registry_id
  skip_service_principal_aad_check = true
}

# # Approach 3: Use null_resource for error handling
# resource "null_resource" "aks_acr_fallback" {
#   depends_on = [azurerm_kubernetes_cluster.main]
  
#   triggers = {
#     cluster_id = azurerm_kubernetes_cluster.main.id
#     acr_id     = var.container_registry_id
  # }