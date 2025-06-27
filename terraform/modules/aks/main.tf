# terraform/modules/aks/main.tf

resource "azurerm_kubernetes_cluster" "main" {
  name                = "aks-${var.project_name}-${var.environment}-${var.resource_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = "${var.project_name}-${var.environment}-${var.resource_suffix}"

  node_resource_group     = "rg-aks-nodes-${var.project_name}-${var.environment}"
  private_cluster_enabled = true
  
  identity {
    type = "SystemAssigned"
  }

  default_node_pool {
    name                = "default"
    vm_size             = var.vm_size
    vnet_subnet_id      = var.aks_subnet_id
    min_count           = null
    max_count           = null
    node_count          = var.node_count
    os_disk_type        = "Managed"
    type                = "VirtualMachineScaleSets"
  }

  network_profile {
    network_plugin = "azure"
    service_cidr   = "10.2.0.0/16"
    dns_service_ip = "10.2.0.10"
  }

  oms_agent {
    log_analytics_workspace_id = var.log_analytics_workspace_id
  }

  azure_policy_enabled = true
  tags = var.tags
}

# Get the private DNS zone created by AKS
data "azurerm_private_dns_zone" "aks" {
  name                = "privatelink.${var.location}.azmk8s.io"
  resource_group_name = azurerm_kubernetes_cluster.main.node_resource_group

  depends_on = [azurerm_kubernetes_cluster.main]
}

# Link Hub VNet to AKS private DNS zone
# This allows jump server (in hub) to resolve AKS private endpoint
resource "azurerm_private_dns_zone_virtual_network_link" "hub_to_aks_dns" {
  name                  = "hub-to-aks-dns-${var.project_name}-${var.environment}"
  resource_group_name   = azurerm_kubernetes_cluster.main.node_resource_group
  private_dns_zone_name = data.azurerm_private_dns_zone.aks.name
  virtual_network_id    = var.hub_vnet_id
  registration_enabled  = false

  tags = var.tags

  depends_on = [
    azurerm_kubernetes_cluster.main,
    data.azurerm_private_dns_zone.aks
  ]
}

# Role assignment for ACR access
resource "azurerm_role_assignment" "aks_acr" {
  count                            = var.create_role_assignments ? 1 : 0
  principal_id                     = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                           = var.container_registry_id
  skip_service_principal_aad_check = true

  lifecycle {
    ignore_changes = [
      principal_id,
      role_definition_name,
      scope
    ]
  }
}