# -----------------------------------------------------------------------------
# Shared locals
# -----------------------------------------------------------------------------

locals {
  # Naming prefix applied to most resources, e.g. "cloudcare-dev".
  name_prefix = "${var.project_name}-${var.environment}"

  # Tags applied to every taggable resource. Caller-supplied tags are merged on
  # top so individual deployments can add their own (cost-centre, owner, etc.).
  common_tags = merge(
    {
      environment = var.environment
      project     = var.project_name
      managed_by  = "terraform"
    },
    var.tags,
  )
}
