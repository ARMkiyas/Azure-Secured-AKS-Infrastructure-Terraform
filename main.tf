
terraform {

  # cloud {
  #   organization = "kiyas-cloud"

  #   workspaces {
  #     name = "cloudcare"
  #   }
  # }
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.1.0"
    }
  }

}


# Configure the Microsoft Azure Provider
provider "azurerm" {
  # skip_provider_registration = true # This is only required when the User, Service Principal, or Identity running Terraform lacks the permissions to register Azure Resource Providers.
  features {}
}




# Create a resource group
resource "azurerm_resource_group" "cloudcareInfra" {
  name     = var.resGroup_name
  location = var.locaion


  tags = {
    env = var.env-tag
  }
}





