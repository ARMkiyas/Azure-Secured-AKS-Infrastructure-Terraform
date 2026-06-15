output "resource_group_name" {
  description = "Name of the resource group holding the infrastructure."
  value       = azurerm_resource_group.main.name
}

output "aks_cluster_name" {
  description = "Name of the AKS cluster."
  value       = azurerm_kubernetes_cluster.aks.name
}

output "aks_node_resource_group" {
  description = "Auto-managed resource group that holds the AKS node resources."
  value       = azurerm_kubernetes_cluster.aks.node_resource_group
}

output "aks_oidc_issuer_url" {
  description = "OIDC issuer URL, used to configure workload identity federation."
  value       = azurerm_kubernetes_cluster.aks.oidc_issuer_url
}

output "vnet_id" {
  description = "Resource ID of the virtual network."
  value       = azurerm_virtual_network.main.id
}

output "frontdoor_endpoint_hostname" {
  description = "Default hostname of the Front Door endpoint."
  value       = azurerm_cdn_frontdoor_endpoint.main.host_name
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace (null when monitoring is disabled)."
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.aks[0].id : null
}

output "argocd_namespace" {
  description = "Namespace where Argo CD is installed (null when disabled)."
  value       = var.enable_argocd ? var.argocd_namespace : null
}

output "argocd_admin_password_command" {
  description = "Command to read the initial Argo CD admin password from the cluster (rotate/disable after SSO setup)."
  value       = var.enable_argocd ? "kubectl -n ${var.argocd_namespace} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d" : null
}

output "kube_config_raw" {
  description = "Raw kubeconfig for the cluster. Sensitive: contains admin credentials."
  value       = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive   = true
}
