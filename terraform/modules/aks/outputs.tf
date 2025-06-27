# terraform/modules/aks/outputs.tf

output "cluster_name" {
  description = "Name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.name
}

output "cluster_id" {
  description = "ID of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.id
}

output "kube_config" {
  description = "Kube config for the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive   = true
}

output "cluster_fqdn" {
  description = "FQDN of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.fqdn
}

output "cluster_private_fqdn" {
  description = "AKS cluster private FQDN"
  value       = azurerm_kubernetes_cluster.main.private_fqdn
}

output "node_resource_group" {
  description = "AKS node resource group name"
  value       = azurerm_kubernetes_cluster.main.node_resource_group
}

output "kubelet_identity" {
  description = "AKS kubelet managed identity"
  value       = azurerm_kubernetes_cluster.main.kubelet_identity
}

output "private_dns_zone_name" {
  description = "Private DNS zone name for AKS"
  value       = data.azurerm_private_dns_zone.aks.name
}

output "private_dns_zone_id" {
  description = "Private DNS zone ID for AKS"
  value       = data.azurerm_private_dns_zone.aks.id
}

output "hub_dns_link_id" {
  description = "Hub VNet to AKS DNS zone link ID"
  value       = azurerm_private_dns_zone_virtual_network_link.hub_to_aks_dns.id
}