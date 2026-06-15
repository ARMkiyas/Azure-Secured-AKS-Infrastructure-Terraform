# -----------------------------------------------------------------------------
# Azure Front Door (Standard/Premium) in front of the internal ingress
# -----------------------------------------------------------------------------
# NOTE: Connecting Front Door to a private origin over Private Link requires the
# Premium_AzureFrontDoor SKU. With Standard, use a public origin instead. Set
# var.frontdoor_sku = "Premium_AzureFrontDoor" if you keep the private_link
# block below.

# The Private Link Service is created by the internal ingress controller (see
# values/ingress-value-internal.yaml) inside the AKS node resource group.
data "azurerm_private_link_service" "ingress" {
  name                = "lbprivateLink"
  resource_group_name = azurerm_kubernetes_cluster.aks.node_resource_group

  depends_on = [helm_release.internal_ingress]
}

resource "azurerm_cdn_frontdoor_profile" "main" {
  name                = "${local.name_prefix}-${var.frontdoor_name}"
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = var.frontdoor_sku

  tags = local.common_tags
}

resource "azurerm_cdn_frontdoor_origin_group" "main" {
  name                     = "origin-group"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id

  health_probe {
    protocol            = "Http"
    request_type        = "GET"
    interval_in_seconds = 100
    path                = "/"
  }

  load_balancing {
    sample_size                        = 4
    successful_samples_required        = 3
    additional_latency_in_milliseconds = 50
  }
}

resource "azurerm_cdn_frontdoor_origin" "main" {
  name                           = "origin"
  cdn_frontdoor_origin_group_id  = azurerm_cdn_frontdoor_origin_group.main.id
  certificate_name_check_enabled = true
  host_name                      = data.azurerm_private_link_service.ingress.alias
  enabled                        = true
  http_port                      = 80
  https_port                     = 443
  priority                       = 1
  weight                         = 1000

  private_link {
    location               = data.azurerm_private_link_service.ingress.location
    private_link_target_id = data.azurerm_private_link_service.ingress.id
    request_message        = "Front Door origin connection request"
  }

  depends_on = [data.azurerm_private_link_service.ingress]
}

resource "azurerm_cdn_frontdoor_endpoint" "main" {
  name                     = "endpoint"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id

  tags = local.common_tags
}

resource "azurerm_cdn_frontdoor_route" "main" {
  name                          = "route"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.main.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.main.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.main.id]
  enabled                       = true

  patterns_to_match = ["/*"]

  # Accept HTTP and HTTPS on the managed endpoint and redirect HTTP to HTTPS so
  # clients always end up on TLS. Front Door terminates TLS with its managed
  # certificate on the *.azurefd.net domain.
  supported_protocols    = ["Http", "Https"]
  https_redirect_enabled = true
}
