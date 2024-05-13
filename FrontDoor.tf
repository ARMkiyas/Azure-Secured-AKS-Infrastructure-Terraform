

data "azurerm_private_link_service" "this" {


  name                = "lbprivateLink"
  resource_group_name = azurerm_kubernetes_cluster.my-aks.node_resource_group
 


  depends_on = [helm_release.nginx-ingress]


}







resource "azurerm_cdn_frontdoor_profile" "frontdoor" {


  name = var.frontdoor_name

  resource_group_name = var.resGroup_name

  sku_name = var.frontdoor_sku



  tags = {
    env = var.env-tag
  }

}




resource "azurerm_cdn_frontdoor_origin_group" "orgingroup" {
  name                     = "origin-group"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.frontdoor.id

  health_probe {
    protocol            = "Http"
    request_type        = "GET"
    interval_in_seconds = "100"
    path                = "/"
  }
  load_balancing {
    sample_size                        = 4
    successful_samples_required        = 3
    additional_latency_in_milliseconds = 50
  }

}



resource "azurerm_cdn_frontdoor_origin" "origin" {


  name                           = "origin"
  cdn_frontdoor_origin_group_id  = azurerm_cdn_frontdoor_origin_group.orgingroup.id
  certificate_name_check_enabled = "true"
  host_name                      = data.azurerm_private_link_service.this.alias

  enabled = "true"

  #   origin_host_header             = "ip"
  http_port  = 80
  https_port = 443
  priority   = 1
  weight     = 1000

  private_link {
    location               = data.azurerm_private_link_service.this.location
    private_link_target_id = data.azurerm_private_link_service.this.id
    request_message        = "Please approve this request"


  }


  depends_on = [data.azurerm_private_link_service.this]


}



resource "azurerm_cdn_frontdoor_endpoint" "endpoint" {

  name                     = "endpoint"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.frontdoor.id

}

resource "azurerm_cdn_frontdoor_route" "thisroute" {
  name = "route"

  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.endpoint.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.orgingroup.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.origin.id]
  enabled                       = "true"


  patterns_to_match   = ["/*"]
  supported_protocols = ["Http"]


  https_redirect_enabled = "false"

}
