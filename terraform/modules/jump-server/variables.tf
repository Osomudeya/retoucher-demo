variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "subnet_id" {
  description = "ID of the subnet for jump server"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "resource_suffix" {
  description = "Resource suffix for unique naming"
  type        = string
}

variable "admin_username" {
  description = "Admin username for the jump server"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key for authentication"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "vnet_id" {
  description = "Hub VNet ID for DNS linking"
  type        = string
  default     = null
}

variable "dns_zone_name" {
  description = "Private DNS zone name for AKS"
  type        = string
  default     = null
}

variable "dns_zone_resource_group" {
  description = "Resource group containing the private DNS zone"
  type        = string
  default     = null
}


variable "arm_client_id" {
  description = "Azure Service Principal Client ID"
  type        = string
}

variable "arm_client_secret" {
  description = "Azure Service Principal Client Secret"
  type        = string
  sensitive   = true
}

variable "arm_tenant_id" {
  description = "Azure Tenant ID"
  type        = string
}

variable "aks_resource_group" {
  description = "AKS resource group name"
  type        = string
}

variable "aks_cluster_name" {
  description = "AKS cluster name"
  type        = string
}

variable "arm_subscription_id" {
  description = "Azure Tenant ID"
  type        = string
}