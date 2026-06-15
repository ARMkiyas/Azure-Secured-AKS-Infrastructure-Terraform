# -----------------------------------------------------------------------------
# Provider / subscription
# -----------------------------------------------------------------------------

variable "subscription_id" {
  description = "Azure Subscription ID to deploy into. Leave null to use ARM_SUBSCRIPTION_ID or the active Azure CLI subscription."
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Global naming / tagging
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Short project name used as a prefix for resource names."
  type        = string
  default     = "cloudcare"

  validation {
    condition     = can(regex("^[a-z0-9]{2,20}$", var.project_name))
    error_message = "project_name must be 2-20 characters of lowercase letters and digits."
  }
}

variable "environment" {
  description = "Deployment environment. Drives naming and the environment tag."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "eastus2"

  validation {
    condition     = length(var.location) > 0
    error_message = "location must not be empty."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group that holds the infrastructure."
  type        = string
  default     = "cloudcare-infra"
}

variable "tags" {
  description = "Additional tags merged onto every resource."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------

variable "network_security_group_name" {
  description = "Name of the network security group associated with the subnets."
  type        = string
  default     = "subnet-nsg"
}

variable "vnet_name" {
  description = "Name of the virtual network (prefixed with the environment)."
  type        = string
  default     = "vnet"
}

variable "vnet_address_space" {
  description = "Address space of the virtual network in CIDR notation."
  type        = list(string)
  default     = ["10.0.0.0/16"]

  validation {
    condition     = length(var.vnet_address_space) > 0
    error_message = "vnet_address_space must contain at least one CIDR block."
  }
}

variable "aks_subnet" {
  description = "Subnet that hosts the AKS node pools."
  type = object({
    name           = string
    address_prefix = string
  })
  default = {
    name           = "aks-subnet"
    address_prefix = "10.0.1.0/24"
  }
}

variable "storage_subnet" {
  description = "Subnet reserved for storage / private endpoints."
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
  description = "Subnet reserved for other supporting services."
  type = object({
    name           = string
    address_prefix = string
  })
  default = {
    name           = "other-service-subnet"
    address_prefix = "10.0.3.0/24"
  }
}

# -----------------------------------------------------------------------------
# AKS
# -----------------------------------------------------------------------------

variable "aks_name" {
  description = "Name of the AKS cluster (prefixed with the environment)."
  type        = string
  default     = "aks"
}

variable "kubernetes_version" {
  description = "Kubernetes control-plane version. Check availability with `az aks get-versions --location <region> -o table`."
  type        = string
  default     = "1.30"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+(\\.[0-9]+)?$", var.kubernetes_version))
    error_message = "kubernetes_version must look like '1.30' or '1.30.4'."
  }
}

variable "aks_sku_tier" {
  description = "AKS control-plane SKU tier. Use Standard or Premium for production (financially backed SLA)."
  type        = string
  default     = "Free"

  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.aks_sku_tier)
    error_message = "aks_sku_tier must be one of: Free, Standard, Premium."
  }
}

variable "enable_azure_rbac" {
  description = "Enable Entra ID (Azure AD) integration with Azure RBAC for Kubernetes authorization."
  type        = bool
  default     = true
}

variable "admin_group_object_ids" {
  description = "Entra ID group object IDs granted cluster-admin when Azure RBAC is enabled."
  type        = list(string)
  default     = []
}

variable "system_node_pool" {
  description = "Configuration for the default (system) node pool."
  type = object({
    vm_size    = string
    node_count = number
    min_count  = number
    max_count  = number
  })
  default = {
    vm_size    = "Standard_DS2_v2"
    node_count = 1
    min_count  = 1
    max_count  = 10
  }

  validation {
    condition     = var.system_node_pool.min_count <= var.system_node_pool.max_count
    error_message = "system_node_pool.min_count must be less than or equal to max_count."
  }
}

variable "aks_network_profile" {
  description = "AKS network profile settings. service_cidr/dns_service_ip must not overlap the VNet address space."
  type = object({
    network_plugin = string
    network_policy = optional(string, "azure")
    service_cidr   = string
    dns_service_ip = string
  })
  default = {
    network_plugin = "azure"
    network_policy = "azure"
    service_cidr   = "10.0.192.0/18"
    dns_service_ip = "10.0.192.10"
  }
}

variable "api_server_authorized_ip_ranges" {
  description = "CIDR ranges allowed to reach the public Kubernetes API server. Empty list means no IP restriction (see .trivyignore / consider private_cluster_enabled)."
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.api_server_authorized_ip_ranges, "0.0.0.0/0")
    error_message = "0.0.0.0/0 defeats the purpose of an API server allowlist; omit it or use a tighter range."
  }
}

# -----------------------------------------------------------------------------
# Observability
# -----------------------------------------------------------------------------

variable "enable_monitoring" {
  description = "Provision a Log Analytics workspace and enable Container Insights (OMS agent) on the cluster."
  type        = bool
  default     = true
}

variable "log_analytics_retention_days" {
  description = "Retention period for the Log Analytics workspace, in days."
  type        = number
  default     = 30

  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "log_analytics_retention_days must be between 30 and 730."
  }
}

# -----------------------------------------------------------------------------
# Front Door
# -----------------------------------------------------------------------------

variable "frontdoor_name" {
  description = "Name of the Azure Front Door (CDN) profile."
  type        = string
  default     = "frontdoor"
}

variable "frontdoor_sku" {
  description = "Front Door SKU. Standard_AzureFrontDoor or Premium_AzureFrontDoor (Premium is required for managed WAF rules and Private Link to private origins on some tiers)."
  type        = string
  default     = "Standard_AzureFrontDoor"

  validation {
    condition     = contains(["Standard_AzureFrontDoor", "Premium_AzureFrontDoor"], var.frontdoor_sku)
    error_message = "frontdoor_sku must be Standard_AzureFrontDoor or Premium_AzureFrontDoor."
  }
}

# -----------------------------------------------------------------------------
# Ingress
# -----------------------------------------------------------------------------

variable "ingress_nginx_chart_version" {
  description = "Pinned ingress-nginx Helm chart version. Pinning avoids surprise upgrades on re-apply. See https://github.com/kubernetes/ingress-nginx/releases."
  type        = string
  default     = "4.11.3"
}
