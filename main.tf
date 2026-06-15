# -----------------------------------------------------------------------------
# Resource group
# -----------------------------------------------------------------------------
# Terraform settings live in versions.tf, provider config in providers.tf,
# shared values in locals.tf and remote state in backend.tf.

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location

  tags = local.common_tags
}
