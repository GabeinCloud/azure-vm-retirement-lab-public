terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
  }
}

provider "azurerm" {
  features {
    resource_group { prevent_deletion_if_contains_resources = false }
  }
}

locals {
  scenario = "ADV-S02"
  common_tags = {
    Workload    = "demo"
    Owner       = var.owner
    Environment = "Demo"
    project     = "azure-vm-retirement-runbook-lab"
    deleteAfter = var.delete_after
    managedBy   = "terraform"
    scenario    = local.scenario
  }
}

resource "azurerm_resource_group" "this" {
  name     = "rg-vm-retirement-adv-s02"
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_virtual_network" "this" {
  name                = "vnet-adv-s02"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = ["10.22.0.0/16"]
  tags                = local.common_tags
}

resource "azurerm_subnet" "this" {
  name                 = "subnet-vms"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.22.1.0/24"]
}

resource "azurerm_network_security_group" "this" {
  name                = "nsg-adv-s02"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.common_tags

  security_rule {
    name                       = "allow-ssh"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.allowed_source_ip
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "deny-all-inbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "this" {
  subnet_id                 = azurerm_subnet.this.id
  network_security_group_id = azurerm_network_security_group.this.id
}

resource "azurerm_public_ip" "this" {
  count               = var.enable_public_ips ? 1 : 0
  name                = "pip-vm-adv-gen1-blocked-01"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

resource "azurerm_network_interface" "this" {
  name                = "nic-vm-adv-gen1-blocked-01"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.common_tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.this.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = var.enable_public_ips ? azurerm_public_ip.this[0].id : null
  }
}

# Gen1 (BIOS) VM deliberately used to demonstrate the boot boundary when targeting v6/v7 NVMe-only families. Dsv5 still accepts Gen1; v6/v7 do not.
# This scenario reproduces the Gen1 -> NVMe-only block.
resource "azurerm_linux_virtual_machine" "this" {
  name                            = "vm-adv-gen1-blocked-01"
  computer_name                   = "gen1blocked"
  location                        = azurerm_resource_group.this.location
  resource_group_name             = azurerm_resource_group.this.name
  size                            = "Standard_D2s_v3"
  admin_username                  = var.admin_username
  admin_password                  = var.linux_admin_password
  disable_password_authentication = false
  network_interface_ids           = [azurerm_network_interface.this.id]
  tags                            = local.common_tags

  dynamic "admin_ssh_key" {
    for_each = var.admin_ssh_public_key_path != "" ? [1] : []
    content {
      username   = var.admin_username
      public_key = file(var.admin_ssh_public_key_path)
    }
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  # Gen1 image, without the -gen2 suffix.
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}

output "resource_group_name" { value = azurerm_resource_group.this.name }
output "vm_name" { value = azurerm_linux_virtual_machine.this.name }
output "public_ip" { value = var.enable_public_ips ? azurerm_public_ip.this[0].ip_address : null }
