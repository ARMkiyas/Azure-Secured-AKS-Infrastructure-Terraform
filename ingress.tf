# -----------------------------------------------------------------------------
# Ingress-NGINX (internal, fronted by Azure Front Door via Private Link)
# -----------------------------------------------------------------------------
# The internal values file annotates the service so AKS provisions an internal
# load balancer and an Azure Private Link Service named "lbprivateLink", which
# Front Door connects to as a private origin (see frontdoor.tf).
#
# To additionally expose a public ingress controller, copy this block, point it
# at values/ingress-value-external.yaml and give it a unique release name.

resource "helm_release" "internal_ingress" {
  name             = "internal"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = var.ingress_nginx_chart_version
  namespace        = "ingress"
  create_namespace = true

  values = [file("${path.module}/values/ingress-value-internal.yaml")]

  # The cluster (and its credentials used by the helm provider) must exist first.
  depends_on = [azurerm_kubernetes_cluster.aks]
}
