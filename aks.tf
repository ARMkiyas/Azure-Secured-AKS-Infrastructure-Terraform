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

  # Kubernetes RBAC. Set explicitly (in addition to the Azure RBAC block below)
  # so static scanners can see it; dynamic blocks are invisible to them.
  role_based_access_control_enabled = true

  # CSI driver to mount Key Vault secrets into pods, with rotation.
  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "5m"
  }

  # Restrict the public API server to known CIDRs when provided. Leave the
  # variable empty only if you accept a publicly reachable API server (gated by
  # Entra ID + RBAC) or you enable private_cluster_enabled.
  dynamic "api_server_access_profile" {
    for_each = length(var.api_server_authorized_ip_ranges) > 0 ? [1] : []
    content {
      authorized_ip_ranges = var.api_server_authorized_ip_ranges
    }
  }

  # Entra ID integration with Kubernetes-native Azure RBAC. Local admin accounts
  # stay enabled so the helm provider can use kube_config on first apply; for a
  # hardened cluster set local_account_disabled and switch to kube_admin_config.
  dynamic "azure_active_directory_role_based_access_control" {
    for_each = var.enable_azure_rbac ? [1] : []
    content {
      azure_rbac_enabled     = true
      admin_group_object_ids = var.admin_group_object_ids
    }
  }

  # Container Insights via the OMS agent, using managed identity auth.
  dynamic "oms_agent" {
    for_each = var.enable_monitoring ? [1] : []
    content {
      log_analytics_workspace_id      = azurerm_log_analytics_workspace.aks[0].id
      msi_auth_for_monitoring_enabled = true
    }
  }

  # Serverless burst capacity: schedule pods onto Azure Container Instances via
  # the Virtual Nodes connector (requires the ACI-delegated subnet in network.tf).
  dynamic "aci_connector_linux" {
    for_each = var.enable_virtual_nodes ? [1] : []
    content {
      subnet_name = azurerm_subnet.virtual_node[0].name
    }
  }

  network_profile {
    network_plugin = var.aks_network_profile.network_plugin
    network_policy = var.aks_network_profile.network_policy
    service_cidr   = var.aks_network_profile.service_cidr
    dns_service_ip = var.aks_network_profile.dns_service_ip
  }

  default_node_pool {
    name                 = "system"
    vm_size              = var.system_node_pool.vm_size
    vnet_subnet_id       = azurerm_subnet.aks.id
    orchestrator_version = var.kubernetes_version
    node_count           = var.system_node_pool.node_count
    min_count            = var.system_node_pool.min_count
    max_count            = var.system_node_pool.max_count

    # Renamed from `enable_auto_scaling` in azurerm v4.0.
    auto_scaling_enabled = true

    # Reserve the system pool for critical addons (CoreDNS, metrics-server,
    # CSI drivers, etc.). This taints the nodes CriticalAddonsOnly=true:NoSchedule
    # so application workloads land on the user / spot pools instead.
    only_critical_addons_enabled = true

    node_labels = {
      role = "system"
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks.id]
  }

  tags = local.common_tags

  # The autoscaler owns node_count after creation; ignore drift on it. The
  # automatic_upgrade_channel ("stable") also manages the cluster/node-pool
  # version, so ignore those too - otherwise every plan after an auto-upgrade
  # would try to revert AKS back to var.kubernetes_version. To change versions
  # via Terraform, temporarily remove these ignores or adjust the channel.
  lifecycle {
    ignore_changes = [
      default_node_pool[0].node_count,
      kubernetes_version,
      default_node_pool[0].orchestrator_version,
    ]
  }

  depends_on = [azurerm_role_assignment.aks_network_contributor]
}
