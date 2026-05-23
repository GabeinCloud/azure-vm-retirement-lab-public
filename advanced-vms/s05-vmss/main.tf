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
  scenario = "ADV-S05"
  common_tags = {
    Workload             = "demo"
    Owner                = "demo"
    Environment          = "Demo"
    project              = "azure-vm-retirement-runbook-lab"
    deleteAfter          = var.delete_after
    managedBy            = "terraform"
    scenario             = local.scenario
  }
}

resource "azurerm_resource_group" "this" {
  name     = "rg-vm-retirement-adv-s05"
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_virtual_network" "this" {
  name                = "vnet-adv-s05"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = ["10.25.0.0/16"]
  tags                = local.common_tags
}

resource "azurerm_subnet" "this" {
  name                 = "subnet-vmss"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.25.1.0/24"]
}

resource "azurerm_network_security_group" "this" {
  name                = "nsg-adv-s05"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.common_tags

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

resource "azurerm_linux_virtual_machine_scale_set" "this" {
  name                            = "vmss-adv-retirement-01"
  resource_group_name             = azurerm_resource_group.this.name
  location                        = azurerm_resource_group.this.location
  sku                             = "Standard_D2s_v3"
  instances                       = 2
  admin_username                  = var.admin_username
  admin_password                  = var.linux_admin_password
  disable_password_authentication = false
  upgrade_mode                    = "Manual"
  tags                            = local.common_tags

  dynamic "admin_ssh_key" {
    for_each = var.admin_ssh_public_key_path != "" ? [1] : []
    content {
      username   = var.admin_username
      public_key = file(var.admin_ssh_public_key_path)
    }
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  network_interface {
    name    = "nic-vmss-adv"
    primary = true

    ip_configuration {
      name      = "ipconfig1"
      primary   = true
      subnet_id = azurerm_subnet.this.id
    }
  }
}

output "resource_group_name" { value = azurerm_resource_group.this.name }
output "vmss_name" { value = azurerm_linux_virtual_machine_scale_set.this.name }
output "vmss_sku" { value = azurerm_linux_virtual_machine_scale_set.this.sku }
output "vmss_instances" { value = azurerm_linux_virtual_machine_scale_set.this.instances }
