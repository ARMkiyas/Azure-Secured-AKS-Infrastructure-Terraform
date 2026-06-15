# -----------------------------------------------------------------------------
# Additional node pools
# -----------------------------------------------------------------------------
# The default (system) pool in aks.tf is reserved for critical addons. These
# pools carry the actual workloads:
#   - user: on-demand, stable capacity for the ingress controller and apps.
#   - spot: cheap, interruptible capacity for fault-tolerant / batch workloads,
#           tainted so only pods that tolerate eviction schedule there.

resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  mode                  = "User"
  vm_size               = var.user_node_pool.vm_size
  vnet_subnet_id        = azurerm_subnet.aks.id
  orchestrator_version  = var.kubernetes_version

  auto_scaling_enabled = true
  min_count            = var.user_node_pool.min_count
  max_count            = var.user_node_pool.max_count

  node_labels = {
    role = "general"
  }

  tags = local.common_tags

  lifecycle {
    ignore_changes = [node_count, orchestrator_version]
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "spot" {
  count = var.enable_spot_node_pool ? 1 : 0

  name                  = "spot"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  mode                  = "User"
  vm_size               = var.spot_node_pool.vm_size
  vnet_subnet_id        = azurerm_subnet.aks.id
  orchestrator_version  = var.kubernetes_version

  # Spot configuration: interruptible VMs at a steep discount.
  priority        = "Spot"
  eviction_policy = "Delete"
  spot_max_price  = var.spot_node_pool.max_price

  auto_scaling_enabled = true
  min_count            = var.spot_node_pool.min_count
  max_count            = var.spot_node_pool.max_count

  # AKS applies these automatically for Spot pools; declaring them keeps the
  # config explicit. Only pods that tolerate the taint schedule onto Spot.
  node_labels = {
    role                                    = "spot"
    "kubernetes.azure.com/scalesetpriority" = "spot"
  }
  node_taints = ["kubernetes.azure.com/scalesetpriority=spot:NoSchedule"]

  tags = local.common_tags

  lifecycle {
    ignore_changes = [node_count, orchestrator_version]
  }
}
