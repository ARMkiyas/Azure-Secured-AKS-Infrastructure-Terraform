output "resource_group_name" {
  value = azurerm_resource_group.cloudcareInfra.name
}

output "aks_name" {
  value = azurerm_kubernetes_cluster.my-aks.name
}
