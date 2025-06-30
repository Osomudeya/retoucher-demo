variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "retoucherirving"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "East US"
}

variable "custom_domain" {
  description = "Custom domain name"
  type        = string
  default     = "retoucherirving.com"
}

# Jump Server Variables
variable "jump_server_admin_username" {
  description = "Admin username for jump server"
  type        = string
  default     = "azureuser"
}

variable "ssh_public_key" {
  description = "SSH public key for jump server access"
  type        = string
}

# AKS Variables
variable "aks_node_count" {
  description = "Number of nodes in AKS cluster"
  type        = number
  default     = 2
}

variable "aks_vm_size" {
  description = "VM size for AKS nodes"
  type        = string
  default     = "Standard_B2s"
}

# Database Variables
variable "database_admin_username" {
  description = "PostgreSQL admin username"
  type        = string
  default     = "adminuser"
}

variable "database_admin_password" {
  description = "PostgreSQL admin password"
  type        = string
  sensitive   = true
}

variable "create_role_assignments" {
  description = "Whether to create role assignments via Terraform (requires User Access Administrator permissions)"
  type        = bool
  default     = true # Default to false to avoid permission issues
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

variable "arm_subscription_id" {
  description = "Azure Tenant ID"
  type        = string
}