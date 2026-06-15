# -----------------------------------------------------------------------------
# Virtual network, subnets and network security group
# -----------------------------------------------------------------------------

resource "azurerm_network_security_group" "main" {
  name                = "${local.name_prefix}-${var.network_security_group_name}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  tags = local.common_tags
}

resource "azurerm_virtual_network" "main" {
  name                = "${local.name_prefix}-${var.vnet_name}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = var.vnet_address_space

  tags = local.common_tags
}

resource "azurerm_subnet" "aks" {
  name                 = var.aks_subnet.name
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.aks_subnet.address_prefix]
}

resource "azurerm_subnet" "storage" {
  name                 = var.storage_subnet.name
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.storage_subnet.address_prefix]
}

resource "azurerm_subnet" "other_service" {
  name                 = var.other_service_subnet.name
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.other_service_subnet.address_prefix]
}

# Associate the NSG with each subnet. In the original configuration the NSG was
# created but never attached to anything, so it had no effect.
resource "azurerm_subnet_network_security_group_association" "aks" {
  subnet_id                 = azurerm_subnet.aks.id
  network_security_group_id = azurerm_network_security_group.main.id
}

resource "azurerm_subnet_network_security_group_association" "storage" {
  subnet_id                 = azurerm_subnet.storage.id
  network_security_group_id = azurerm_network_security_group.main.id
}

resource "azurerm_subnet_network_security_group_association" "other_service" {
  subnet_id                 = azurerm_subnet.other_service.id
  network_security_group_id = azurerm_network_security_group.main.id
}
