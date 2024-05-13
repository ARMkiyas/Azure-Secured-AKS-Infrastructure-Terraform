variable "resGroup_name" {
  type        = string
  default     = "azure_static_app"
  description = "resource group name"
}

variable "locaion" {
  type        = string
  default     = "eastus2"
  description = "description"
}

variable "env-tag" {
  default     = "dev"
  description = "environment"

}

variable "subnet_sec_group" {
  type        = string
  default     = "subnet_sec_group"
  description = "subnet security group"

}

variable "vnet_name" {
  type        = string
  default     = "vnet"
  description = "vnet name"

}

variable "vnet_address_space" {
  type        = list(string)
  default     = ["10.0.0.0/16"]
  description = "vnet address space"

}

variable "aks_subnet" {
  type = object({
    name           = string
    address_prefix = string
  })
  default = {
    name           = "aks-subnet"
    address_prefix = "10.0.1.0/24"
  }
  description = "aks subnet"

}


variable "storage_subnet" {
  type = object({
    name           = string
    address_prefix = string
  })
  default = {
    name           = "storage-subnet"
    address_prefix = "10.0.2.0/24"
  }

}

variable "other_service_subnet" {
  type = object({
    name           = string
    address_prefix = string
  })
  default = {
    name           = "other-service-subnet"
    address_prefix = "10.0.3.0/24"
  }


}





variable "aks_name" {
  default     = "aks"
  description = "aks name"

}

variable "kube_version" {
  default     = "1.28.5"
  description = "kubernetes version"
}


variable "frontdoor_name" {

  default     = "frontdoor"
  description = "azure frontdoor name"

}


variable "frontdoor_sku" {
  default     = "Standard_AzureFrontDoor"
  description = "azure frontdoor sku (default: Standard_AzureFrontDoor)"

}
