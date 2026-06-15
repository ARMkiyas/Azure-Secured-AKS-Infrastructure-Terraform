# -----------------------------------------------------------------------------
# Observability: Log Analytics workspace for Container Insights
# -----------------------------------------------------------------------------
# Wired into the cluster via the oms_agent block in aks.tf. Disable by setting
# var.enable_monitoring = false (e.g. for ephemeral dev clusters).

resource "azurerm_log_analytics_workspace" "aks" {
  count = var.enable_monitoring ? 1 : 0

  name                = "${local.name_prefix}-logs"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days

  tags = local.common_tags
}
