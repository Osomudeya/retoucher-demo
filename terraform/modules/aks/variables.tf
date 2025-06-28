# terraform/modules/aks/variables.tf

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "resource_suffix" {
  description = "Random suffix for resource names"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "aks_subnet_id" {
  description = "AKS subnet ID (in spoke VNet)"
  type        = string
}

variable "node_count" {
  description = "Number of AKS nodes"
  type        = number
  default     = 3
}

variable "vm_size" {
  description = "Size of the AKS nodes"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID"
  type        = string
}

variable "container_registry_id" {
  description = "Container registry ID for role assignment"
  type        = string
}

variable "create_role_assignments" {
  description = "Whether to create role assignments"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}


# # terraform/modules/aks/variables.tf

# variable "resource_group_name" {
#   description = "Name of the resource group"
#   type        = string
# }

# variable "location" {
#   description = "Azure region"
#   type        = string
# }

# # variable "subnet_id" {
# #   description = "ID of the subnet for AKS"
# #   type        = string
# # }

# variable "environment" {
#   description = "Environment name"
#   type        = string
# }

# variable "project_name" {
#   description = "Project name"
#   type        = string
# }

# variable "resource_suffix" {
#   description = "Resource suffix for unique naming"
#   type        = string
# }

# variable "vm_size" {
#   description = "VM size for AKS nodes"
#   type        = string
#   default     = "Standard_B2s"
# }

# variable "container_registry_id" {
#   description = "ID of the Azure Container Registry"
#   type        = string
# }

# variable "log_analytics_workspace_id" {
#   description = "ID of the Log Analytics Workspace"
#   type        = string
# }

# variable "tags" {
#   description = "Tags to apply to resources"
#   type        = map(string)
#   default     = {}
# }

# variable "create_role_assignments" {
#   description = "Whether to create role assignments via Terraform (requires elevated permissions)"
#   type        = bool
#   default     = true
# }

# # variable "vnet_id" {
# #   description = "Virtual Network ID - Required for private DNS zone linking"
# #   type        = string
# # }

# # Hub-and-Spoke networking variables
# variable "aks_subnet_id" {
#   description = "AKS subnet ID (in spoke VNet)"
#   type        = string
# }

# variable "hub_vnet_id" {
#   description = "Hub Virtual Network ID - Required for jump server DNS resolution"
#   type        = string
# }

# variable "node_count" {
#   description = "Number of AKS nodes"
#   type        = number
#   default     = 3
# }