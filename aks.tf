

resource "azurerm_user_assigned_identity" "bese" {
  name                = "base"
  location            = azurerm_resource_group.cloudcareInfra.location
  resource_group_name = azurerm_resource_group.cloudcareInfra.name
}

resource "azurerm_role_assignment" "base" {
  scope                = azurerm_resource_group.cloudcareInfra.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.bese.principal_id
}

resource "azurerm_kubernetes_cluster" "my-aks" {

  name                = "${var.env-tag}-${var.aks_name}"
  location            = azurerm_resource_group.cloudcareInfra.location
  resource_group_name = azurerm_resource_group.cloudcareInfra.name
  kubernetes_version  = var.kube_version
  dns_prefix          = "cloudcare"

  automatic_channel_upgrade = "stable"
  private_cluster_enabled   = false
  node_resource_group       = "${var.env-tag}-${var.aks_name}-${var.resGroup_name}-node-rg"


  sku_tier = "Free"

  # http_application_routing_enabled = true


  oidc_issuer_enabled       = true
  workload_identity_enabled = true


  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "5m"
  }

  network_profile {
    network_plugin = "azure"
    dns_service_ip = "10.0.192.10"
    service_cidr   = "10.0.192.0/18"

  }



  default_node_pool {
    name                 = "general"
    vm_size              = "Standard_DS2_v2"
    vnet_subnet_id       = azurerm_subnet.aks_subnet.id
    orchestrator_version = var.kube_version
    enable_auto_scaling  = true
    node_count           = 1
    min_count            = 1
    max_count            = 10

    node_labels = {
      role = "general"
    }

  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.bese.id]
  }

  tags = {
    env = var.env-tag
  }

  lifecycle {
    ignore_changes = [default_node_pool[0].node_count]
  }

  depends_on = [azurerm_role_assignment.base]




}
