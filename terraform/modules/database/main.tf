# terraform/modules/database/main.tf

# Create Private DNS Zone for PostgreSQL
resource "azurerm_private_dns_zone" "postgres" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Link DNS zone to Spoke VNet
resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "postgres-dns-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = var.vnet_id
  tags                  = var.tags
}


resource "azurerm_postgresql_flexible_server" "main" {
  name                = "psql-${var.project_name}-${var.environment}-${var.resource_suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  version             = "13"

  delegated_subnet_id = var.subnet_id
  private_dns_zone_id = azurerm_private_dns_zone.postgres.id

  administrator_login           = var.admin_username
  administrator_password        = var.admin_password
  public_network_access_enabled = false

  storage_mb            = 32768
  sku_name              = "B_Standard_B1ms"
  backup_retention_days = 7

  # high_availability {
  #   mode                      = "ZoneRedundant"
  #   standby_availability_zone = "2"
  # }

  tags = var.tags

  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.postgres,
  ]

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}


# # PostgreSQL Flexible Server - VNet Integration ONLY
# resource "azurerm_postgresql_flexible_server" "main" {
#   name                   = "psql-${var.project_name}-${var.environment}-${var.resource_suffix}"
#   resource_group_name    = var.resource_group_name
#   location              = var.location
#   version               = "13"

#   # VNet Integration (secure private access)
#   delegated_subnet_id   = var.subnet_id
#   private_dns_zone_id   = azurerm_private_dns_zone.postgres.id

#   administrator_login    = var.admin_username
#   administrator_password = var.admin_password

#   # No public access (secure)
#   public_network_access_enabled = false

#   storage_mb = 32768  # 32 GB
#   sku_name   = "B_Standard_B1ms"  # Burstable tier

#   backup_retention_days = 7
#   # Remove geo_redundant_backup_enabled - not supported on B tier

#   tags = var.tags

#   depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]
# }

# PostgreSQL Database - wait for server to be fully ready
resource "azurerm_postgresql_flexible_server_database" "webapp" {
  name      = "webapp"
  server_id = azurerm_postgresql_flexible_server.main.id
  collation = "en_US.utf8"
  charset   = "utf8"

  # Explicit dependency + timeout
  depends_on = [azurerm_postgresql_flexible_server.main]

  timeouts {
    create = "15m"
    delete = "15m"
  }
}

# PostgreSQL Configuration - ONLY VALID PARAMETERS
# resource "azurerm_postgresql_flexible_server_configuration" "log_statement" {
#   name      = "log_statement"
#   server_id = azurerm_postgresql_flexible_server.main.id
#   value     = "all"
# }

# resource "azurerm_postgresql_flexible_server_configuration" "log_duration" {
#   name      = "log_duration"
#   server_id = azurerm_postgresql_flexible_server.main.id
#   value     = "on"
# }

# resource "azurerm_postgresql_flexible_server_configuration" "log_connections" {
#   name      = "log_connections"
#   server_id = azurerm_postgresql_flexible_server.main.id
#   value     = "on"
# }

# resource "azurerm_postgresql_flexible_server_configuration" "log_disconnections" {
#   name      = "log_disconnections"
#   server_id = azurerm_postgresql_flexible_server.main.id
#   value     = "on"
# }

# Note: Removed invalid configurations:
# - ssl (read-only parameter)
# - connection_throttling (not supported in PostgreSQL 13)
# - password_encryption (managed by Azure)
# - private_endpoint (not compatible with VNet integration)
# - firewall rules (not needed with VNet integration)



# # PostgreSQL Flexible Server
# resource "azurerm_postgresql_flexible_server" "main" {
#   name                   = "psql-${var.project_name}-${var.environment}-${var.resource_suffix}"
#   resource_group_name    = var.resource_group_name
#   location              = var.location
#   version               = "13"
#   delegated_subnet_id   = var.subnet_id
#   private_dns_zone_id   = azurerm_private_dns_zone.postgres.id
#   administrator_login    = var.admin_username
#   administrator_password = var.admin_password
#   public_network_access_enabled = false

#   storage_mb = 32768  # 32 GB
#   sku_name   = "B_Standard_B1ms"  # Burstable tier for cost optimization

#   backup_retention_days = 7
#   geo_redundant_backup_enabled = true

#   tags = var.tags

#   depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]
# }

# # PostgreSQL Database
# resource "azurerm_postgresql_flexible_server_database" "webapp" {
#   name      = "webapp"
#   server_id = azurerm_postgresql_flexible_server.main.id
#   collation = "en_US.utf8"
#   charset   = "utf8"
# }

# # PostgreSQL Firewall Rule (allow access from AKS subnet)
# resource "azurerm_postgresql_flexible_server_firewall_rule" "aks_access" {
#   name             = "aks-access"
#   server_id        = azurerm_postgresql_flexible_server.main.id
#   start_ip_address = "10.1.1.0"
#   end_ip_address   = "10.1.1.255"
# }

# # Create Private DNS Zone for PostgreSQL
# resource "azurerm_private_dns_zone" "postgres" {
#   name                = "privatelink.postgres.database.azure.com"
#   resource_group_name = var.resource_group_name
#   tags               = var.tags
# }

# # Link DNS zone to Spoke VNet
# resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
#   name                  = "postgres-dns-link"
#   resource_group_name   = var.resource_group_name
#   private_dns_zone_name = azurerm_private_dns_zone.postgres.name
#   virtual_network_id    = var.vnet_id
#   tags                 = var.tags
# }

# # PostgreSQL Configuration for monitoring
# resource "azurerm_postgresql_flexible_server_configuration" "log_statement" {
#   name      = "log_statement"
#   server_id = azurerm_postgresql_flexible_server.main.id
#   value     = "all"
# }

# resource "azurerm_postgresql_flexible_server_configuration" "log_duration" {
#   name      = "log_duration"
#   server_id = azurerm_postgresql_flexible_server.main.id
#   value     = "on"
# }

# # Additional security configurations
# resource "azurerm_postgresql_flexible_server_configuration" "password_encryption" {
#   name      = "password_encryption"
#   server_id = azurerm_postgresql_flexible_server.main.id
#   value     = "scram-sha-256"
# }

# resource "azurerm_postgresql_flexible_server_configuration" "ssl" {
#   name      = "ssl"
#   server_id = azurerm_postgresql_flexible_server.main.id
#   value     = "on"
# }

# resource "azurerm_postgresql_flexible_server_configuration" "connection_throttling" {
#   name      = "connection_throttling"
#   server_id = azurerm_postgresql_flexible_server.main.id
#   value     = "on"
# }

# resource "azurerm_postgresql_flexible_server_configuration" "log_connections" {
#   name      = "log_connections"
#   server_id = azurerm_postgresql_flexible_server.main.id
#   value     = "on"
# }

# resource "azurerm_postgresql_flexible_server_configuration" "log_disconnections" {
#   name      = "log_disconnections"
#   server_id = azurerm_postgresql_flexible_server.main.id
#   value     = "on"
# }

# # Azure Private Link for PostgreSQL
# resource "azurerm_private_endpoint" "postgres" {
#   name                = "pe-postgres-${var.project_name}-${var.environment}"
#   location            = var.location
#   resource_group_name = var.resource_group_name
#   subnet_id           = var.subnet_id

#   private_service_connection {
#     name                           = "psc-postgres-${var.project_name}-${var.environment}"
#     private_connection_resource_id = azurerm_postgresql_flexible_server.main.id
#     is_manual_connection          = false
#     subresource_names            = ["postgresqlServer"]
#   }

#   private_dns_zone_group {
#     name                 = "default"
#     private_dns_zone_ids = [azurerm_private_dns_zone.postgres.id]
#   }

#   tags = var.tags
# }