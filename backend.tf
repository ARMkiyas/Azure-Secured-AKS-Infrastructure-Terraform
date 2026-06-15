# -----------------------------------------------------------------------------
# Remote state backend
# -----------------------------------------------------------------------------
# Local state is the default and is fine for experimentation, but it is NOT safe
# for teams or production: there is no locking, encryption, or audit history.
#
# For any shared or production use, store state remotely in an Azure Storage
# Account. Create the backing storage once (outside this configuration, e.g. a
# small bootstrap config or the Azure CLI), then uncomment and fill in the block
# below and run `terraform init -migrate-state`.
#
# Example bootstrap (run once, replace the placeholders):
#   az group create -n tfstate-rg -l eastus2
#   az storage account create -n <globally-unique-name> -g tfstate-rg \
#       -l eastus2 --sku Standard_LRS --min-tls-version TLS1_2 \
#       --allow-blob-public-access false
#   az storage container create -n tfstate --account-name <globally-unique-name>
#
# terraform {
#   backend "azurerm" {
#     resource_group_name  = "tfstate-rg"
#     storage_account_name = "<globally-unique-name>"
#     container_name       = "tfstate"
#     key                  = "aks/dev/terraform.tfstate"
#     use_azuread_auth     = true # authenticate to the backend with your Entra ID identity
#   }
# }
