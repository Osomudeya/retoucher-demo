# terraform/modules/monitoring/main.tf - FIXED VERSION

# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${var.project_name}-${var.environment}-${var.resource_suffix}"
  location           = var.location
  resource_group_name = var.resource_group_name
  sku                = "PerGB2018"
  retention_in_days  = 30
  tags              = var.tags
}

# Application Insights
resource "azurerm_application_insights" "main" {
  name                = "appi-${var.project_name}-${var.environment}-${var.resource_suffix}"
  location           = var.location
  resource_group_name = var.resource_group_name
  workspace_id       = azurerm_log_analytics_workspace.main.id
  application_type   = "web"
  tags              = var.tags
}

# Azure Managed Grafana - FIXED VERSION
resource "azurerm_dashboard_grafana" "main" {
  name                              = "grafana-${var.resource_suffix}"
  resource_group_name               = var.resource_group_name
  location                         = var.location
  
  # FIXED: Use version 10 instead of 9
  grafana_major_version            = "10"
  
  api_key_enabled                  = true
  deterministic_outbound_ip_enabled = true
  public_network_access_enabled    = true
  
  identity {
    type = "SystemAssigned"
  }
  
  tags = var.tags
}

# Data source configuration for current subscription
data "azurerm_client_config" "current" {}

# Conditional Grafana Role Assignment
resource "azurerm_role_assignment" "grafana_reader" {
  count                = var.create_role_assignments ? 1 : 0
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "Monitoring Reader"
  principal_id         = azurerm_dashboard_grafana.main.identity[0].principal_id

  lifecycle {
    create_before_destroy = true
  }
}

# Fallback: Create role assignment via Azure CLI
# resource "terraform_data" "grafana_role_fallback" {
#   count = var.create_role_assignments ? 0 : 1
  
#   triggers_replace = {
#     grafana_id = azurerm_dashboard_grafana.main.id
#     subscription_id = data.azurerm_client_config.current.subscription_id
#   }

#   provisioner "local-exec" {
#     command = <<-EOT
#       echo "🔗 Creating Grafana role assignment via Azure CLI..."
#       az role assignment create \
#         --assignee ${azurerm_dashboard_grafana.main.identity[0].principal_id} \
#         --role "Monitoring Reader" \
#         --scope "/subscriptions/${data.azurerm_client_config.current.subscription_id}" \
#         --only-show-errors || echo "⚠️ Role assignment failed or already exists"
#     EOT
#   }
# }

# Action Group for alerts
resource "azurerm_monitor_action_group" "main" {
  name                = "actiongroup-${var.project_name}-${var.environment}"
  resource_group_name = var.resource_group_name
  short_name          = "webapp-ag"
  
  email_receiver {
    name          = "admin"
    email_address = "admin@${var.project_name}.com"
  }
  
  tags = var.tags
}



# # Log Analytics Workspace
# resource "azurerm_log_analytics_workspace" "main" {
#   name                = "law-${var.project_name}-${var.environment}-${var.resource_suffix}"
#   location           = var.location
#   resource_group_name = var.resource_group_name
#   sku                = "PerGB2018"
#   retention_in_days  = 30
#   tags              = var.tags
# }

# # Application Insights
# resource "azurerm_application_insights" "main" {
#   name                = "appi-${var.project_name}-${var.environment}-${var.resource_suffix}"
#   location           = var.location
#   resource_group_name = var.resource_group_name
#   workspace_id       = azurerm_log_analytics_workspace.main.id
#   application_type   = "web"
#   tags              = var.tags
# }

# # Azure Managed Grafana
# resource "azurerm_dashboard_grafana" "main" {
#   name                              = "grafana-${var.resource_suffix}"
#   resource_group_name               = var.resource_group_name
#   location                         = var.location
#   grafana_major_version            = 9
#   api_key_enabled                  = true
#   deterministic_outbound_ip_enabled = true
#   public_network_access_enabled    = true

#   identity {
#     type = "SystemAssigned"
#   }

#   tags = var.tags
# }

# # Grant Grafana access to monitor resources
# resource "azurerm_role_assignment" "grafana_reader" {
#   scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
#   role_definition_name = "Monitoring Reader"
#   principal_id         = azurerm_dashboard_grafana.main.identity[0].principal_id
# }

# # Data source configuration for current subscription
# data "azurerm_client_config" "current" {}

# # Action Group for alerts
# resource "azurerm_monitor_action_group" "main" {
#   name                = "actiongroup-${var.project_name}-${var.environment}"
#   resource_group_name = var.resource_group_name
#   short_name          = "webapp-ag"

#   email_receiver {
#     name          = "admin"
#     email_address = "admin@${var.project_name}.com"
#   }

#   tags = var.tags
# }

# # Metric Alert for high CPU usage
# # Fixed version - using Container Insights metrics
# resource "azurerm_monitor_metric_alert" "high_cpu" {
#   name                = "high-cpu-alert"
#   resource_group_name = var.resource_group_name
#   scopes              = [var.aks_cluster_id]  # We need to pass this from main.tf
#   description         = "Alert when AKS CPU usage is high"

#   criteria {
#     metric_namespace = "Microsoft.ContainerService/managedClusters"
#     metric_name      = "node_cpu_usage_percentage"
#     aggregation      = "Average"
#     operator         = "GreaterThan"
#     threshold        = 80

#     dimension {
#       name     = "node"
#       operator = "Include"
#       values   = ["*"]
#     }
#   }

#   action {
#     action_group_id = azurerm_monitor_action_group.main.id
#   }

#   tags = var.tags
# }