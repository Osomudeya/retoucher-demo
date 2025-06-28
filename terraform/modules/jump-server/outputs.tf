output "public_ip_address" {
  description = "Public IP address of the jump server"
  value       = azurerm_public_ip.jump_server.ip_address
}

output "private_ip_address" {
  description = "Private IP address of the jump server"
  value       = azurerm_network_interface.jump_server.private_ip_address
}

output "vm_name" {
  description = "Name of the jump server VM"
  value       = azurerm_linux_virtual_machine.jump_server.name
}

# terraform/modules/jump-server/outputs.tf

output "public_ip" {
  description = "Public IP address of the jump server"
  value       = azurerm_public_ip.jump_server.ip_address
}

output "private_ip" {
  description = "Private IP address of the jump server"
  value       = azurerm_network_interface.jump_server.private_ip_address
}

output "dns_link_id" {
  description = "ID of the DNS zone virtual network link"
  value       = var.vnet_id != null && var.dns_zone_name != null && var.dns_zone_resource_group != null ? azurerm_private_dns_zone_virtual_network_link.hub_to_aks_dns[0].id : null
}