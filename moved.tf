# -----------------------------------------------------------------------------
# State migration (moved blocks)
# -----------------------------------------------------------------------------
# These blocks map the OLD resource addresses (from the pre-upgrade layout) to
# the new, consistently named ones so `terraform apply` migrates state in place
# instead of destroying and recreating resources.
#
# If you are deploying this configuration fresh (no prior state), these are
# harmless no-ops. You can safely delete this file after your first successful
# `terraform apply` against pre-existing state.

moved {
  from = azurerm_resource_group.cloudcareInfra
  to   = azurerm_resource_group.main
}

moved {
  from = azurerm_network_security_group.net_sec_group
  to   = azurerm_network_security_group.main
}

moved {
  from = azurerm_virtual_network.vps
  to   = azurerm_virtual_network.main
}

moved {
  from = azurerm_subnet.aks_subnet
  to   = azurerm_subnet.aks
}

moved {
  from = azurerm_subnet.storage_subnet
  to   = azurerm_subnet.storage
}

moved {
  from = azurerm_subnet.other_service_subnet
  to   = azurerm_subnet.other_service
}

moved {
  from = azurerm_user_assigned_identity.bese
  to   = azurerm_user_assigned_identity.aks
}

moved {
  from = azurerm_role_assignment.base
  to   = azurerm_role_assignment.aks_network_contributor
}

moved {
  from = azurerm_kubernetes_cluster.my-aks
  to   = azurerm_kubernetes_cluster.aks
}

moved {
  from = azurerm_cdn_frontdoor_profile.frontdoor
  to   = azurerm_cdn_frontdoor_profile.main
}

moved {
  from = azurerm_cdn_frontdoor_origin_group.orgingroup
  to   = azurerm_cdn_frontdoor_origin_group.main
}

moved {
  from = azurerm_cdn_frontdoor_origin.origin
  to   = azurerm_cdn_frontdoor_origin.main
}

moved {
  from = azurerm_cdn_frontdoor_endpoint.endpoint
  to   = azurerm_cdn_frontdoor_endpoint.main
}

moved {
  from = azurerm_cdn_frontdoor_route.thisroute
  to   = azurerm_cdn_frontdoor_route.main
}

moved {
  from = helm_release.nginx-ingress
  to   = helm_release.internal_ingress
}
