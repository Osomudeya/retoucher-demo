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

# Jump Server Virtual Machine
resource "azurerm_linux_virtual_machine" "jump_server" {
  name                = "vm-jumpserver-${var.project_name}-${var.environment}-${var.resource_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  size                = "Standard_B1s" # Smallest size for cost optimization
  admin_username      = var.admin_username

  # Disable password authentication, use SSH keys only
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

  # Custom script to install required tools
  custom_data = base64encode(templatefile("${path.root}/../scripts/setup-jump-server.sh", {
    admin_username = var.admin_username
  }))

  tags = var.tags
}