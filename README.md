# Azure Secured AKS Infrastructure (Terraform)

Terraform configuration that provisions a network-isolated **Azure Kubernetes Service (AKS)** platform fronted by **Azure Front Door** over **Private Link**. Public traffic terminates at Front Door and reaches the cluster through an internal ingress-nginx controller, so the Kubernetes load balancer is never exposed directly to the internet.

```
                 Internet
                    │  HTTPS (TLS terminated at the managed *.azurefd.net domain)
                    ▼
          ┌───────────────────┐
          │  Azure Front Door │   profile + endpoint + route + origin group
          └─────────┬─────────┘
                    │  Private Link (private origin)
                    ▼
          ┌───────────────────────────────────────────┐
          │  Azure Private Link Service "lbprivateLink" │  (created by ingress-nginx)
          │  → internal Standard Load Balancer          │
          └─────────┬───────────────────────────────────┘
                    ▼
          ┌───────────────────────────────────────────┐
          │  AKS cluster (private internal ingress)     │
          │  VNet 10.0.0.0/16                            │
          │   ├─ aks-subnet            10.0.1.0/24       │
          │   ├─ storage-subnet        10.0.2.0/24       │
          │   └─ other-service-subnet  10.0.3.0/24       │
          │  All subnets attached to one NSG            │
          └─────────────────────────────────────────────┘
```

## Contents

- [Architecture](#architecture)
- [Repository layout](#repository-layout)
- [Requirements](#requirements)
- [Quick start](#quick-start)
- [Configuration](#configuration)
- [Inputs](#inputs)
- [Outputs](#outputs)
- [Connecting to the cluster](#connecting-to-the-cluster)
- [Security notes](#security-notes)
- [Remote state](#remote-state)
- [Upgrading from the previous version](#upgrading-from-the-previous-version)
- [Day-2 operations](#day-2-operations)
- [Troubleshooting](#troubleshooting)

## Architecture

| Component | Resource(s) | Purpose |
|-----------|-------------|---------|
| Resource group | `azurerm_resource_group.main` | Container for all managed resources |
| Networking | `azurerm_virtual_network.main`, three `azurerm_subnet.*`, `azurerm_network_security_group.main` + associations | Isolated VNet with dedicated subnets, each attached to an NSG |
| Identity | `azurerm_user_assigned_identity.aks` + `azurerm_role_assignment.aks_network_contributor` | User-assigned identity for the cluster, scoped to Network Contributor on the resource group |
| AKS | `azurerm_kubernetes_cluster.aks` | Cluster with autoscaling system node pool, OIDC issuer, workload identity and the Key Vault CSI secrets provider |
| Ingress | `helm_release.internal_ingress` | ingress-nginx in internal mode, which provisions an internal LB + Private Link Service |
| Front Door | `azurerm_cdn_frontdoor_*` | Global entry point connecting privately to the internal ingress |

## Repository layout

```
.
├── versions.tf                 # Terraform + provider version constraints
├── providers.tf                # azurerm + helm provider configuration
├── backend.tf                  # Remote state backend (commented template)
├── locals.tf                   # name_prefix + common_tags
├── variables.tf                # All input variables (typed, validated, documented)
├── main.tf                     # Resource group
├── network.tf                  # VNet, subnets, NSG + associations
├── aks.tf                      # AKS cluster + identity + role assignment
├── ingress.tf                  # ingress-nginx Helm release
├── frontdoor.tf                # Azure Front Door profile/endpoint/origin/route
├── outputs.tf                  # Useful outputs
├── moved.tf                    # State migration from the old resource names
├── terraform.tfvars.example    # Copy to terraform.tfvars and edit
└── values/
    ├── ingress-value-internal.yaml   # Internal ingress (Private Link enabled)
    └── ingress-value-external.yaml   # Public ingress (optional)
```

## Requirements

| Tool | Version |
|------|---------|
| Terraform | `>= 1.9, < 2.0` |
| azurerm provider | `~> 4.0` (tested with 4.77) |
| helm provider | `~> 3.0` (tested with 3.2) |
| Azure CLI | recent, authenticated (`az login`) |
| kubectl / helm | for cluster operations |

The identity running Terraform needs permission to create the resources above and to assign the **Network Contributor** role on the resource group (i.e. `Microsoft.Authorization/roleAssignments/write`, typically **Owner** or **User Access Administrator** on the scope).

## Quick start

```bash
# 1. Authenticate and select a subscription
az login
az account set --subscription "<your-subscription-id>"
export ARM_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"

# 2. Provide variable values
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars

# 3. Initialise providers
terraform init

# 4. Review the plan
terraform fmt -check
terraform validate
terraform plan -out=tfplan

# 5. Apply the reviewed plan artifact
terraform apply tfplan
```

> The first `apply` creates the cluster, installs ingress-nginx (which creates the Private Link Service), and then wires up Front Door. Because Front Door reads the Private Link Service via a data source, all of this resolves within a single apply thanks to the explicit `depends_on` chain.

## Configuration

Set values in `terraform.tfvars` (preferred) or pass `-var`/`-var-file` on the command line. The subscription can be supplied three ways, in order of precedence:

1. `subscription_id` variable
2. `ARM_SUBSCRIPTION_ID` environment variable
3. Active Azure CLI subscription

> azurerm **v4.0 made the subscription ID mandatory** — one of the three must be set.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `subscription_id` | `string` | `null` | Target subscription; falls back to `ARM_SUBSCRIPTION_ID` / Azure CLI |
| `project_name` | `string` | `"cloudcare"` | Name prefix (lowercase, 2-20 chars) |
| `environment` | `string` | `"dev"` | One of `dev`, `staging`, `prod` |
| `location` | `string` | `"eastus2"` | Azure region |
| `resource_group_name` | `string` | `"cloudcare-infra"` | Resource group name |
| `tags` | `map(string)` | `{}` | Extra tags merged onto every resource |
| `network_security_group_name` | `string` | `"subnet-nsg"` | NSG name |
| `vnet_name` | `string` | `"vnet"` | VNet name (prefixed) |
| `vnet_address_space` | `list(string)` | `["10.0.0.0/16"]` | VNet CIDR(s) |
| `aks_subnet` | `object` | `aks-subnet / 10.0.1.0/24` | AKS node subnet |
| `storage_subnet` | `object` | `storage-subnet / 10.0.2.0/24` | Storage / private-endpoint subnet |
| `other_service_subnet` | `object` | `other-service-subnet / 10.0.3.0/24` | Supporting services subnet |
| `aks_name` | `string` | `"aks"` | Cluster name (prefixed) |
| `kubernetes_version` | `string` | `"1.30"` | Control-plane version |
| `aks_sku_tier` | `string` | `"Free"` | `Free`, `Standard` or `Premium` |
| `system_node_pool` | `object` | DS2_v2, 1/1/10 | Default node pool sizing |
| `aks_network_profile` | `object` | azure / 10.0.192.0/18 / .10 | CNI + service CIDR |
| `frontdoor_name` | `string` | `"frontdoor"` | Front Door profile name (prefixed) |
| `frontdoor_sku` | `string` | `"Standard_AzureFrontDoor"` | Front Door SKU |
| `ingress_nginx_chart_version` | `string` | `"4.11.3"` | Pinned ingress-nginx chart version |

Most resources are named `${project_name}-${environment}-...` (e.g. `cloudcare-dev-aks`).

## Outputs

| Name | Description |
|------|-------------|
| `resource_group_name` | Resource group name |
| `aks_cluster_name` | AKS cluster name |
| `aks_node_resource_group` | Auto-managed node resource group |
| `aks_oidc_issuer_url` | OIDC issuer URL for workload identity federation |
| `vnet_id` | Virtual network resource ID |
| `frontdoor_endpoint_hostname` | Default `*.azurefd.net` hostname |
| `kube_config_raw` | Raw kubeconfig (**sensitive**) |

## Connecting to the cluster

```bash
az aks get-credentials \
  --resource-group "$(terraform output -raw resource_group_name)" \
  --name "$(terraform output -raw aks_cluster_name)"

kubectl get nodes
kubectl -n ingress get svc
```

## Security notes

- **No direct public exposure.** The ingress is internal; only Front Door reaches it, over Private Link.
- **HTTP is redirected to HTTPS** at the Front Door route, with TLS terminated on the managed domain.
- **Workload identity + OIDC** are enabled so pods can use federated credentials instead of stored secrets.
- **Key Vault CSI driver** with secret rotation is enabled for mounting secrets.
- **NSGs are now attached** to every subnet (previously the NSG was created but never associated).
- **Least-privilege provider registration**: only the resource providers this stack needs are auto-registered.

Recommended hardening before production:

- Set `aks_sku_tier = "Standard"` (or `Premium`) for an SLA-backed control plane.
- Consider `private_cluster_enabled = true` to keep the API server off the public internet.
- Add Azure Policy / Defender for Containers and a Front Door **WAF** policy (managed WAF rules require the `Premium_AzureFrontDoor` SKU).
- Restrict the NSG with explicit rules rather than relying on defaults.
- Move state to a remote backend (see below).

> **Private Link origin requires Premium Front Door.** Connecting Front Door to a private origin over Private Link is a `Premium_AzureFrontDoor` capability. With the `Standard` SKU, either upgrade the SKU or switch to a public origin.

## Remote state

Local state has **no locking, encryption, or history** and must not be used for teams or production. `backend.tf` contains a ready-to-use `azurerm` backend template — create the storage account/container, uncomment the block, fill in the values, and run:

```bash
terraform init -migrate-state
```

State paths follow `aks/<environment>/terraform.tfstate` so multiple environments stay isolated.

## Upgrading from the previous version

This revision modernises an older configuration. Key changes:

- **azurerm `~> 3.100` → `~> 4.0`.** v4.0 makes `subscription_id` mandatory and renames AKS arguments: `automatic_channel_upgrade → automatic_upgrade_channel`, `enable_auto_scaling → auto_scaling_enabled`, `enable_node_public_ip → node_public_ip_enabled`, `enable_host_encryption → host_encryption_enabled`. These are already applied.
- **Resources renamed** for consistency (e.g. `cloudcareInfra → main`, `my-aks → aks`, `bese → aks`). `moved.tf` maps old addresses to new ones so existing state migrates in place — no destroy/recreate.
- **helm `>= 2.1.0` → `~> 3.0`.** v3.0 migrated to the Terraform Plugin Framework: the provider's `kubernetes` block is now a nested object attribute (`kubernetes = { ... }`), already applied in `providers.tf`.
- **Provider config split** into `versions.tf` / `providers.tf`; the helm provider now reads cluster credentials directly instead of via a redundant data source.
- **Variables** are fully typed, validated and documented; typos fixed (`locaion → location`, `env-tag → environment`, `kube_version → kubernetes_version`, etc.).
- **NSG associations**, pinned ingress chart version, HTTP→HTTPS redirect, and richer outputs added.

Migration steps for an existing deployment:

```bash
terraform init -upgrade
terraform plan        # confirm the plan shows "moved" and no destroys of stateful resources
terraform apply
```

After the first successful apply against existing state, `moved.tf` can be deleted.

## Day-2 operations

- **Format & validate:** `terraform fmt -recursive && terraform validate`
- **Static security scan:** `trivy config .` and/or `checkov -d .`
- **Upgrade Kubernetes:** bump `kubernetes_version` (check `az aks get-versions --location <region> -o table`); the `stable` auto-upgrade channel also keeps patches current.
- **Scale:** adjust `system_node_pool.{min_count,max_count}`. The autoscaler owns `node_count`, which is ignored via `lifecycle.ignore_changes`.
- Keep provider/runtime upgrades in a **separate PR** from functional changes, and always commit `.terraform.lock.hcl`.

## Troubleshooting

| Symptom | Likely cause / fix |
|---------|--------------------|
| `subscription_id is required` | Set `ARM_SUBSCRIPTION_ID` or the `subscription_id` variable (azurerm v4 requirement) |
| Front Door origin fails to create with Private Link | The `Standard` SKU does not support private origins — use `Premium_AzureFrontDoor` or a public origin |
| `data "azurerm_private_link_service" "ingress"` not found | The internal ingress release hasn't finished creating the PLS; re-run `apply`. The name must match `azure-pls-name` in `values/ingress-value-internal.yaml` (`lbprivateLink`) |
| Helm provider auth errors | Ensure the cluster exists first; the provider reads `azurerm_kubernetes_cluster.aks.kube_config` |
| Plan wants to destroy/recreate after rename | Make sure `moved.tf` is present before running `plan` |

---

Generated/validated with Terraform 1.15, azurerm 4.77, helm 3.2.
