terraform {
  # Pin the runtime to a minor series. Terraform 1.9+ is required for
  # cross-variable validation used in variables.tf.
  required_version = ">= 1.9, < 2.0"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # Major version 4.x. Note: v4.0 made `subscription_id` mandatory and
      # renamed several AKS arguments (handled in aks.tf).
      version = "~> 4.0"
    }
    helm = {
      source = "hashicorp/helm"
      # v3.x migrated to the Terraform Plugin Framework: the `kubernetes`
      # block is now a nested object attribute (see providers.tf).
      version = "~> 3.0"
    }
  }
}
