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
  scenario = "ADV-S03"
  common_tags = {
    Workload    = "demo"
    Owner       = "demo"
    Environment = "Demo"
    project     = "azure-vm-retirement-runbook-lab"
    deleteAfter = var.delete_after
    managedBy   = "terraform"
    scenario    = local.scenario
  }
  vms = ["vm-adv-avset-01", "vm-adv-avset-02"]
}

resource "azurerm_resource_group" "this" {
  name     = "rg-vm-retirement-adv-s03"
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_virtual_network" "this" {
  name                = "vnet-adv-s03"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = ["10.23.0.0/16"]
  tags                = local.common_tags
}

resource "azurerm_subnet" "this" {
  name                 = "subnet-vms"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.23.1.0/24"]
}

resource "azurerm_network_security_group" "this" {
  name                = "nsg-adv-s03"
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

resource "azurerm_availability_set" "this" {
  name                         = "avset-adv-s03"
  location                     = azurerm_resource_group.this.location
  resource_group_name          = azurerm_resource_group.this.name
  platform_fault_domain_count  = 2
  platform_update_domain_count = 5
  managed                      = true
  tags                         = local.common_tags
}

resource "azurerm_public_ip" "this" {
  for_each            = var.enable_public_ips ? toset(local.vms) : toset([])
  name                = "pip-${each.key}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

resource "azurerm_network_interface" "this" {
  for_each            = toset(local.vms)
  name                = "nic-${each.key}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.common_tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.this.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = var.enable_public_ips ? azurerm_public_ip.this[each.key].id : null
  }
}

resource "azurerm_linux_virtual_machine" "this" {
  for_each                        = toset(local.vms)
  name                            = each.key
  computer_name                   = replace(each.key, "vm-adv-avset-", "asnode")
  location                        = azurerm_resource_group.this.location
  resource_group_name             = azurerm_resource_group.this.name
  size                            = "Standard_D2s_v3"
  admin_username                  = var.admin_username
  admin_password                  = var.linux_admin_password
  disable_password_authentication = false
  availability_set_id             = azurerm_availability_set.this.id
  network_interface_ids           = [azurerm_network_interface.this[each.key].id]
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

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}

output "resource_group_name" { value = azurerm_resource_group.this.name }
output "availability_set" { value = azurerm_availability_set.this.name }
output "vms" { value = [for k, v in azurerm_linux_virtual_machine.this : v.name] }
