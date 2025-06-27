output "hub_vnet_id" {
  description = "ID of the hub virtual network"
  value       = azurerm_virtual_network.hub.id
}

output "spoke_vnet_id" {
  description = "ID of the spoke virtual network"
  value       = azurerm_virtual_network.spoke.id
}

output "jump_server_subnet_id" {
  description = "ID of the jump server subnet"
  value       = azurerm_subnet.jump_server.id
}

output "aks_subnet_id" {
  description = "ID of the AKS subnet"
  value       = azurerm_subnet.aks.id
}

output "database_subnet_id" {
  description = "ID of the database subnet"
  value       = azurerm_subnet.database.id
}

output "hub_vnet_name" {
  description = "Hub Virtual Network name"
  value       = azurerm_virtual_network.hub.name
}

output "spoke_vnet_name" {
  description = "Spoke Virtual Network name"
  value       = azurerm_virtual_network.spoke.name
}

output "vnet_id" {
  description = "Primary Virtual Network ID (Spoke VNet for backward compatibility)"
  value       = azurerm_virtual_network.spoke.id
}
