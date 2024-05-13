data "azurerm_kubernetes_cluster" "this" {
  name                = "${var.env-tag}-${var.aks_name}"
  resource_group_name = var.resGroup_name


}


provider "helm" {

  kubernetes {
    host                   = data.azurerm_kubernetes_cluster.this.kube_config.0.host
    client_certificate     = base64decode(data.azurerm_kubernetes_cluster.this.kube_config.0.client_certificate)
    client_key             = base64decode(data.azurerm_kubernetes_cluster.this.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.this.kube_config.0.cluster_ca_certificate)



  }


}




# resource "helm_release" "nginx-ingress" {
#   name = "external"

#   repository       = "https://kubernetes.github.io/ingress-nginx"
#   chart            = "ingress-nginx"
#   create_namespace = true
#   namespace        = "ingress"



#   values = [file("${path.module}/values/ingress-value-external.yaml")]

# }




resource "helm_release" "nginx-ingress" {
  name = "internal"

  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  create_namespace = true
  namespace        = "ingress"

  values = [file("${path.module}/values/ingress-value-internal.yaml")]





}
