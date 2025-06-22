# terraform/modules/monitoring/variables.tf

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region"
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

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

# NEW: Control role assignment creation
variable "create_role_assignments" {
  description = "Whether to create role assignments via Terraform (requires elevated permissions)"
  type        = bool
  default     = true
}