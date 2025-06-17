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