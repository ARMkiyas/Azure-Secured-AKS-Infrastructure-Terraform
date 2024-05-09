

resource "azurerm_network_security_group" "net_sec_group" {
  resource_group_name = azurerm_resource_group.cloudcareInfra.name
  location            = azurerm_resource_group.cloudcareInfra.location
  name                = var.subnet_sec_group

}

resource "azurerm_virtual_network" "vps" {
  name                = "${var.env-tag}-${var.vnet_name}"
  resource_group_name = azurerm_resource_group.cloudcareInfra.name
  location            = azurerm_resource_group.cloudcareInfra.location
  address_space       = var.vnet_address_space




  tags = {
    env = var.env-tag
  }
}



resource "azurerm_subnet" "aks_subnet" {
  name                 = var.aks_subnet.name
  resource_group_name  = azurerm_resource_group.cloudcareInfra.name
  virtual_network_name = azurerm_virtual_network.vps.name
  address_prefixes     = [var.aks_subnet.address_prefix]

}

resource "azurerm_subnet" "storage_subnet" {
  name                 = var.storage_subnet.name
  resource_group_name  = azurerm_resource_group.cloudcareInfra.name
  virtual_network_name = azurerm_virtual_network.vps.name
  address_prefixes     = [var.storage_subnet.address_prefix]
}

resource "azurerm_subnet" "other_service_subnet" {
  name                 = var.other_service_subnet.name
  resource_group_name  = azurerm_resource_group.cloudcareInfra.name
  virtual_network_name = azurerm_virtual_network.vps.name
  address_prefixes     = [var.other_service_subnet.address_prefix]

}
