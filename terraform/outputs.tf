output "resource_group_name" {
  description = "Name of the main resource group"
  value       = azurerm_resource_group.main.name
}

output "aks_cluster_name" {
  description = "Name of the AKS cluster"
  value       = module.aks.cluster_name
}

output "container_registry_login_server" {
  description = "ACR login server URL"
  value       = azurerm_container_registry.main.login_server
}

output "container_registry_admin_username" {
  description = "ACR admin username"
  value       = azurerm_container_registry.main.admin_username
  sensitive   = true
}

output "container_registry_admin_password" {
  description = "ACR admin password"
  value       = azurerm_container_registry.main.admin_password
  sensitive   = true
}

output "jump_server_public_ip" {
  description = "Public IP address of the jump server"
  value       = module.jump_server.public_ip
}


output "database_fqdn" {
  description = "PostgreSQL server FQDN"
  value       = module.database.fqdn
}

output "application_insights_instrumentation_key" {
  description = "Application Insights instrumentation key"
  value       = module.monitoring.application_insights_instrumentation_key
  sensitive   = true
}

output "log_analytics_workspace_id" {
  description = "Log Analytics Workspace ID"
  value       = module.monitoring.log_analytics_workspace_id
}

# Ingress Public IP for your domain
output "ingress_public_ip" {
  description = "Public IP address for ingress (use this in your DNS)"
  value       = azurerm_public_ip.ingress_ip.ip_address
}

# DNS Zone Name Servers (configure these in your domain registrar)
output "dns_zone_name_servers" {
  description = "Name servers for your DNS zone - configure these in your domain registrar"
  value       = azurerm_dns_zone.domain.name_servers
}

output "aks_resource_group" {
  description = "Resource group containing AKS cluster"
  value       = azurerm_resource_group.main.name
}

# Container Registry
output "acr_login_server" {
  description = "Login server for Azure Container Registry"
  value       = azurerm_container_registry.main.login_server
}

output "aks_node_resource_group" {
  description = "AKS node resource group (where DNS zone is created)"
  value       = module.aks.node_resource_group
}

output "calculated_dns_zone_name" {
  description = "Calculated DNS zone name for AKS private endpoint"
  value       = join(".", slice(split(".", module.aks.cluster_private_fqdn), 1, length(split(".", module.aks.cluster_private_fqdn))))
}

output "aks_private_fqdn" {
  description = "AKS cluster private FQDN"
  value       = module.aks.cluster_private_fqdn
}