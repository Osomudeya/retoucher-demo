# terraform/modules/jump-server/main.tf


# Public IP for Jump Server
resource "azurerm_public_ip" "jump_server" {
  name                = "pip-jumphost-${var.project_name}-${var.environment}-${var.resource_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# Network Interface for Jump Server 
resource "azurerm_network_interface" "jump_server" {
  name                = "nic-jumphost-${var.project_name}-${var.environment}-${var.resource_suffix}"
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
  name                = "nsg-jumphost-${var.project_name}-${var.environment}-${var.resource_suffix}"
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
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = var.tags
}

# Associate NSG with Network Interface
resource "azurerm_network_interface_security_group_association" "jump_server" {
  network_interface_id      = azurerm_network_interface.jump_server.id
  network_security_group_id = azurerm_network_security_group.jump_server.id
}

# Jump Server Virtual Machine - NEW NAME AND DISK NAME
resource "azurerm_linux_virtual_machine" "jump_server" {
  name                            = "jumphost-vm-${var.project_name}-${var.environment}"
  location                        = var.location
  resource_group_name             = var.resource_group_name
  network_interface_ids           = [azurerm_network_interface.jump_server.id]
  size                            = "Standard_DS1_v2"
  computer_name                   = "jumphostvm"
  admin_username                  = var.admin_username
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    name                 = "jumphost-os-disk-${var.resource_suffix}"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  tags = var.tags


  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = var.admin_username
      private_key = file("~/.ssh/retoucherirving_azure")
      host        = self.public_ip_address
      timeout     = "10m"
    }

    inline = [
      # Update system
      "sudo apt-get update -y",
      "sudo apt-get install -y curl wget unzip git jq",

      # Install Azure CLI
      "curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash",

      # Install kubectl
      "curl -LO https://dl.k8s.io/release/v1.28.0/bin/linux/amd64/kubectl",
      "sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl",
      "rm kubectl",

      # Install Helm  
      "curl https://get.helm.sh/helm-v3.12.0-linux-amd64.tar.gz -o helm.tar.gz",
      "tar -zxvf helm.tar.gz",
      "sudo mv linux-amd64/helm /usr/local/bin/",
      "rm -rf linux-amd64 helm.tar.gz",

      # Create directories
      "mkdir -p ~/.kube ~/deployments",

      # Success message
      "echo 'Jump server tools installed successfully!'",
      "echo 'Use: az login (interactive) then az aks get-credentials to configure kubectl'"
    ]

    on_failure = continue
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "hubnetdnsconfig" {
  name                  = "hubnetdnsconfig"
  resource_group_name   = var.dns_zone_resource_group
  private_dns_zone_name = var.dns_zone_name
  virtual_network_id    = var.vnet_id

  tags = {
    purpose = "dns-link"
  }
}


# # terraform/modules/jump-server/main.tf

# # Public IP for Jump Server
# resource "azurerm_public_ip" "jump_server" {
#   name                = "pip-jumpserver-${var.project_name}-${var.environment}-${var.resource_suffix}"
#   location            = var.location
#   resource_group_name = var.resource_group_name
#   allocation_method   = "Static"
#   sku                 = "Standard"
#   tags                = var.tags
# }

# # Network Interface for Jump Server
# resource "azurerm_network_interface" "jump_server" {
#   name                = "nic-jumpserver-${var.project_name}-${var.environment}-${var.resource_suffix}"
#   location            = var.location
#   resource_group_name = var.resource_group_name

#   ip_configuration {
#     name                          = "internal"
#     subnet_id                     = var.subnet_id
#     private_ip_address_allocation = "Dynamic"
#     public_ip_address_id          = azurerm_public_ip.jump_server.id
#   }

#   tags = var.tags
# }

# # Network Security Group for Jump Server
# resource "azurerm_network_security_group" "jump_server" {
#   name                = "nsg-jumpserver-${var.project_name}-${var.environment}-${var.resource_suffix}"
#   location            = var.location
#   resource_group_name = var.resource_group_name

#   security_rule {
#     name                       = "SSH"
#     priority                   = 1001
#     direction                  = "Inbound"
#     access                     = "Allow"
#     protocol                   = "Tcp"
#     source_port_range          = "*"
#     destination_port_range     = "22"
#     source_address_prefix      = "*"  # You may want to restrict this
#     destination_address_prefix = "*"
#   }

#   tags = var.tags
# }

# # Associate NSG with Network Interface
# resource "azurerm_network_interface_security_group_association" "jump_server" {
#   network_interface_id      = azurerm_network_interface.jump_server.id
#   network_security_group_id = azurerm_network_security_group.jump_server.id
# }

# # Jump Server Virtual Machine
# resource "azurerm_linux_virtual_machine" "jump_server" {
#   name                            = "jumpservervm-${var.project_name}-${var.environment}"
#   location                        = var.location
#   resource_group_name             = var.resource_group_name
#   network_interface_ids           = [azurerm_network_interface.jump_server.id]  # FIXED: Correct reference
#   size                            = "Standard_DS1_v2"
#   computer_name                   = "jumpservervm"
#   admin_username                  = var.admin_username
#   disable_password_authentication = true

#   admin_ssh_key {
#     username   = var.admin_username
#     public_key = var.ssh_public_key
#   }

#   os_disk {
#     name                 = "jumpserverOsDisk"
#     caching              = "ReadWrite"
#     storage_account_type = "Premium_LRS"
#   }

#   source_image_reference {
#     publisher = "Canonical"
#     offer     = "0001-com-ubuntu-server-jammy"
#     sku       = "22_04-lts"
#     version   = "latest"
#   }

#   tags = var.tags
# }


# # DNS LINKING
# resource "azurerm_private_dns_zone_virtual_network_link" "hubnetdnsconfig" {
#   name                  = "hubnetdnsconfig"
#   resource_group_name   = var.dns_zone_resource_group
#   private_dns_zone_name = var.dns_zone_name
#   virtual_network_id    = var.vnet_id

#  tags = {
#     purpose = "dns-link"
#   }
# }