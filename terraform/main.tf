# main.tf
#
# WHAT: The actual infrastructure — resource group, network, NSG, public IP,
#       NIC, and the Ubuntu VM itself.
# HOW THIS FITS: This is the Terraform equivalent of everything you did
#       manually in SOP §3 (Azure Portal VM creation). Once this is applied,
#       you pick back up at SOP §4 (SSH in, install Splunk) exactly the
#       same way — Terraform's job ends at "infrastructure exists and is
#       reachable," not at "Splunk is installed."

resource "azurerm_resource_group" "splunk" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "splunk" {
  name                = var.vnet_name
  address_space       = var.vnet_address_space
  location            = azurerm_resource_group.splunk.location
  resource_group_name = azurerm_resource_group.splunk.name
  tags                = var.tags
}

resource "azurerm_subnet" "splunk" {
  name                 = var.subnet_name
  resource_group_name  = azurerm_resource_group.splunk.name
  virtual_network_name = azurerm_virtual_network.splunk.name
  address_prefixes     = var.subnet_prefix
}

# ------------------------------------------------------------------
# Network Security Group — the firewall. THIS IS THE SECURITY-CRITICAL
# BLOCK. Three rules, each scoped as tightly as the lab doc specifies:
#   - SSH (22)   -> your IP only
#   - Web UI (8000) -> your IP only
#   - Forwarder (9997) -> the AD VNet's CIDR only, never public
# Azure NSGs are STATEFUL and DEFAULT-DENY for inbound — anything not
# explicitly allowed here is already blocked.
# ------------------------------------------------------------------
resource "azurerm_network_security_group" "splunk" {
  name                = var.nsg_name
  location            = azurerm_resource_group.splunk.location
  resource_group_name = azurerm_resource_group.splunk.name
  tags                = var.tags

  security_rule {
    name                       = "Allow-SSH-MyIP"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.my_ip_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-SplunkWebUI-MyIP"
    priority                   = 310
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8000"
    source_address_prefix      = var.my_ip_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-SplunkForwarder-ADVNet"
    priority                   = 320
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9997"
    source_address_prefix      = var.ad_vnet_cidr
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "splunk" {
  subnet_id                 = azurerm_subnet.splunk.id
  network_security_group_id = azurerm_network_security_group.splunk.id
}

# ------------------------------------------------------------------
# Public IP — Static, so it survives VM stop/start.
# ------------------------------------------------------------------
resource "azurerm_public_ip" "splunk" {
  name                = "${var.vm_name}-pip"
  location            = azurerm_resource_group.splunk.location
  resource_group_name = azurerm_resource_group.splunk.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_network_interface" "splunk" {
  name                = "${var.vm_name}-nic"
  location            = azurerm_resource_group.splunk.location
  resource_group_name = azurerm_resource_group.splunk.name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.splunk.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.splunk.id
  }
}

# ------------------------------------------------------------------
# The VM itself — Ubuntu 22.04 LTS, SSH-key auth ONLY (no password
# auth — set explicitly below so it's visible in code review, not
# buried in a provider default someone has to look up).
# ------------------------------------------------------------------
resource "azurerm_linux_virtual_machine" "splunk" {
  name                = var.vm_name
  location            = azurerm_resource_group.splunk.location
  resource_group_name = azurerm_resource_group.splunk.name
  size                = var.vm_size
  admin_username      = var.admin_username
  tags                = var.tags

  network_interface_ids = [
    azurerm_network_interface.splunk.id,
  ]

  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(pathexpand(var.ssh_public_key_path))
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}