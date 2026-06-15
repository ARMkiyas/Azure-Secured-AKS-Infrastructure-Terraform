# -----------------------------------------------------------------------------
# Provider configuration
# -----------------------------------------------------------------------------

provider "azurerm" {
  # subscription_id is mandatory from azurerm v4.0 onwards. It can be supplied
  # here via var.subscription_id, or left null to fall back to the
  # ARM_SUBSCRIPTION_ID environment variable / Azure CLI active subscription.
  subscription_id = var.subscription_id

  # Only register the resource providers actually needed by this stack rather
  # than the legacy "register everything" behaviour.
  resource_provider_registrations = "core"
  resource_providers_to_register = [
    "Microsoft.ContainerService",
    "Microsoft.KeyVault",
    "Microsoft.Network",
    "Microsoft.Cdn",
  ]

  features {}
}

# The Helm provider is configured directly from the credentials of the cluster
# created in aks.tf. kube_config is only known after the cluster exists, so the
# first apply provisions the cluster before any helm_release is evaluated.
# Helm provider v3 expects `kubernetes` as a nested object attribute (= { ... }).
provider "helm" {
  kubernetes = {
    host                   = azurerm_kubernetes_cluster.aks.kube_config[0].host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate)
  }
}
