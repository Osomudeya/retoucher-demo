# terraform/modules/jump-server/main.tf

# Public IP for Jump Server
resource "azurerm_public_ip" "jump_server" {
  name                = "pip-jumpserver-${var.project_name}-${var.environment}-${var.resource_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# Network Interface for Jump Server
resource "azurerm_network_interface" "jump_server" {
  name                = "nic-jumpserver-${var.project_name}-${var.environment}-${var.resource_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.jump_server.id
  }

  tags = var.tags
}

# Network Security Group for Jump Server
resource "azurerm_network_security_group" "jump_server" {
  name                = "nsg-jumpserver-${var.project_name}-${var.environment}-${var.resource_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"  # You may want to restrict this
    destination_address_prefix = "*"
  }

  tags = var.tags
}

# Associate NSG with Network Interface
resource "azurerm_network_interface_security_group_association" "jump_server" {
  network_interface_id      = azurerm_network_interface.jump_server.id
  network_security_group_id = azurerm_network_security_group.jump_server.id
}

# Jump Server Virtual Machine
resource "azurerm_linux_virtual_machine" "jump_server" {
  name                = "vm-jumpserver-${var.project_name}-${var.environment}-${var.resource_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  size                = "Standard_B1s"
  admin_username      = var.admin_username

  disable_password_authentication = true

  network_interface_ids = [
    azurerm_network_interface.jump_server.id,
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }

  tags = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "hub_to_aks_dns" {
  count = var.vnet_id != null && var.dns_zone_name != null && var.dns_zone_resource_group != null ? 1 : 0
  
  name                  = "hub-to-aks-dns-${var.project_name}-${var.environment}"
  resource_group_name   = var.dns_zone_resource_group
  private_dns_zone_name = var.dns_zone_name
  virtual_network_id    = var.vnet_id
  registration_enabled  = false
  
  tags = merge(var.tags, {
    purpose = "dns-link"
  })
}