# -----------------------------------------------------------------------------
# AKS cluster identity and role assignment
# -----------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "aks" {
  name                = "${local.name_prefix}-aks-identity"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = local.common_tags
}

# The cluster identity needs Network Contributor on the resource group so it can
# manage load balancers, the internal Private Link Service and route tables.
resource "azurerm_role_assignment" "aks_network_contributor" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

# -----------------------------------------------------------------------------
# AKS cluster
# -----------------------------------------------------------------------------

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "${local.name_prefix}-${var.aks_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kubernetes_version  = var.kubernetes_version
  dns_prefix          = local.name_prefix
  node_resource_group = "${local.name_prefix}-${var.aks_name}-nodes-rg"
  sku_tier            = var.aks_sku_tier

  # Keep the cluster patched automatically on the stable channel.
  # Renamed from `automatic_channel_upgrade` in azurerm v4.0.
  automatic_upgrade_channel = "stable"

  private_cluster_enabled = false

  # Workload identity federation (preferred over the deprecated AAD pod identity).
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # CSI driver to mount Key Vault secrets into pods, with rotation.
  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "5m"
  }

  network_profile {
    network_plugin = var.aks_network_profile.network_plugin
    service_cidr   = var.aks_network_profile.service_cidr
    dns_service_ip = var.aks_network_profile.dns_service_ip
  }

  default_node_pool {
    name                 = "general"
    vm_size              = var.system_node_pool.vm_size
    vnet_subnet_id       = azurerm_subnet.aks.id
    orchestrator_version = var.kubernetes_version
    node_count           = var.system_node_pool.node_count
    min_count            = var.system_node_pool.min_count
    max_count            = var.system_node_pool.max_count

    # Renamed from `enable_auto_scaling` in azurerm v4.0.
    auto_scaling_enabled = true

    node_labels = {
      role = "general"
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks.id]
  }

  tags = local.common_tags

  # The autoscaler owns node_count after creation; ignore drift on it.
  lifecycle {
    ignore_changes = [default_node_pool[0].node_count]
  }

  depends_on = [azurerm_role_assignment.aks_network_contributor]
}
