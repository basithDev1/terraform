provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

data "azurerm_resource_group" "rg" {
  name = "newRG"

}


resource "azurerm_virtual_network" "vnet" {
  name                = "projectVnet"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
  address_space       = ["192.16.0.0/16"]

  tags = {
    environment = "Production"
  }

}
resource "azurerm_subnet" "webSubnet" {
  name                 = "webSubnet"
  resource_group_name  = data.azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["192.16.1.0/24"]
}


# Subnet for Azure Bastion
resource "azurerm_subnet" "AzureBastionSubnet" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = data.azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["192.16.2.0/24"]
}

# Subnet for Azure Firewall
resource "azurerm_subnet" "AzureFirewallSubnet" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = data.azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["192.16.3.0/24"] # Unique address space
}

resource "azurerm_network_interface" "vmNIC" {
  name                = "projectVmNic"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "vnicIP"
    subnet_id                     = azurerm_subnet.webSubnet.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "192.16.1.5"
  }
}

resource "azurerm_virtual_machine" "vm" {
  name                  = "projectVm"
  location              = data.azurerm_resource_group.rg.location
  resource_group_name   = data.azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.vmNIC.id]
  vm_size               = "Standard_D2s_v3"

  # Uncomment this line to delete the OS disk automatically when deleting the VM
  delete_os_disk_on_termination = true

  # Uncomment this line to delete the data disks automatically when deleting the VM
  delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
  storage_os_disk {
    name              = "myosdisk1"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }
  os_profile {
    computer_name  = "user01"
    admin_username = "Ajstudent@12"
    admin_password = "Ajstudent@12"
  }
  os_profile_linux_config {
    disable_password_authentication = false
  }
  tags = {
    environment = "staging"
  }
}

resource "azurerm_public_ip" "firewallPip" {
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  name                = "firewallPip"
  allocation_method   = "Static"
  sku                 = "Standard"

}

resource "azurerm_firewall" "projectFirewall" {
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  name                = "projectFirewall"
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"

  ip_configuration {
    name                 = "ipConfigFirewall"
    subnet_id            = azurerm_subnet.AzureFirewallSubnet.id
    public_ip_address_id = azurerm_public_ip.firewallPip.id
  }


}

resource "azurerm_firewall_policy" "firewallPolicy" {
  name                = "azureFirewallPolicy"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  #   rule_collection_groups=[azurerm_firewall_policy_rule_collection_group.ruleColletion]

}

resource "azurerm_firewall_policy_rule_collection_group" "ruleColletion" {
  name               = "projectFirewallRuleCollection"
  firewall_policy_id = azurerm_firewall_policy.firewallPolicy.id
  priority           = 100

  #   network_rule_collection {
  #     name     = "networkRuleCollection"
  #     priority = 100
  #     action   = "Allow"

  #     rule {
  #       name                  = "allow-from-specific-ip"
  #       source_addresses      = ["27.4.221.14"]
  #       destination_addresses = ["192.16.1.5/24"] # Adjust as needed (e.g., specific IPs or subnets)
  #       destination_ports     = ["80", ]          # Adjust ports as needed
  #       protocols             = ["TCP"]
  #     }
  #   }

  nat_rule_collection {
    name     = "dnat_port_3000_to_80"
    priority = 200
    action   = "Dnat"

    rule {
      name                = "translate-port-3000-to-80"
      source_addresses    = ["27.4.221.14"]
      destination_ports   = ["3000"]
      destination_address = azurerm_public_ip.firewallPip.ip_address
      translated_address  = "192.16.1.5"
      translated_port     = "80"
      protocols           = ["TCP"]
    }
  }
}
