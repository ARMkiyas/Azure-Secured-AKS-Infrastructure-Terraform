# Azure Secured AKS Infrastructure (Terraform)- test ci


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
├── monitoring.tf               # Log Analytics workspace (Container Insights)
├── ingress.tf                  # ingress-nginx Helm release
├── frontdoor.tf                # Azure Front Door profile/endpoint/origin/route
├── outputs.tf                  # Useful outputs
├── moved.tf                    # State migration from the old resource names
├── terraform.tfvars.example    # Copy to terraform.tfvars and edit
├── .tflint.hcl                 # TFLint rules (terraform + azurerm presets)
├── .trivyignore                # Documented, time-boxed Trivy exceptions
├── .pre-commit-config.yaml     # fmt / validate / tflint / trivy / docs hooks
├── .github/
│   ├── workflows/              # CI: validate → lint → security scan → plan
│   └── dependabot.yml          # Weekly action-SHA + provider updates
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
| `enable_azure_rbac` | `bool` | `true` | Enable Entra ID + Azure RBAC for Kubernetes auth |
| `admin_group_object_ids` | `list(string)` | `[]` | Entra ID groups granted cluster-admin |
| `system_node_pool` | `object` | DS2_v2, 1/1/10 | Default node pool sizing |
| `aks_network_profile` | `object` | azure / azure / 10.0.192.0/18 / .10 | CNI plugin, network policy + service CIDR |
| `api_server_authorized_ip_ranges` | `list(string)` | `[]` | CIDRs allowed to reach the public API server (empty = unrestricted) |
| `enable_monitoring` | `bool` | `true` | Provision Log Analytics + Container Insights |
| `log_analytics_retention_days` | `number` | `30` | Workspace retention (30-730) |
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
| `log_analytics_workspace_id` | Log Analytics workspace ID (null if monitoring disabled) |
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
- **Entra ID + Azure RBAC** for Kubernetes authorization is enabled by default (`enable_azure_rbac`); grant access with `admin_group_object_ids`. Kubernetes RBAC is also set explicitly (`role_based_access_control_enabled = true`).
- **Network policy** (`azure` by default) is enabled so traffic between pods can be restricted with NetworkPolicy objects. Note: the network policy cannot be changed in place on an existing cluster — it requires replacement.
- **API server allowlist**: set `api_server_authorized_ip_ranges` to your egress CIDRs to restrict the public API server. Left empty by default (public, gated by Entra ID + RBAC); see the accepted-risk note below.
- **Container Insights** (Log Analytics + OMS agent with managed-identity auth) is enabled by default for cluster observability.
- **Key Vault CSI driver** with secret rotation is enabled for mounting secrets.
- **NSGs are now attached** to every subnet (previously the NSG was created but never associated).
- **Least-privilege provider registration**: only the resource providers this stack needs are auto-registered.

Recommended hardening before production:

- Set `aks_sku_tier = "Standard"` (or `Premium`) for an SLA-backed control plane.
- Consider `private_cluster_enabled = true` to keep the API server off the public internet, and `local_account_disabled = true` to force Entra ID auth (then drive the helm provider from `kube_admin_config`).
- Run workloads on a dedicated user node pool and reserve the system pool with `only_critical_addons_enabled` (add an `azurerm_kubernetes_cluster_node_pool`).
- Add Azure Policy / Defender for Containers and a Front Door **WAF** policy (managed WAF rules require the `Premium_AzureFrontDoor` SKU).
- Restrict the NSG with explicit rules rather than relying on defaults.
- Move state to a remote backend (see below).

## Quality gates

Static checks run both locally (via pre-commit) and in CI before any plan:

```bash
# One-time local setup
pre-commit install
pre-commit run --all-files     # fmt, validate, tflint, trivy, terraform-docs

# Or run tools directly
terraform fmt -check -recursive
terraform validate
tflint --init && tflint --recursive
trivy config .
```

`.github/workflows/terraform.yml` runs **validate → lint → security scan → plan** on every PR. The plan job authenticates to Azure with **OIDC / workload identity** (no stored secrets) and uploads the plan as an artifact so a downstream apply consumes the *reviewed* plan rather than re-planning. Configure these repository secrets for the plan job: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`.

### Supply-chain hardening of the pipeline

- **All third-party actions are pinned to a commit SHA** (with a `# vX.Y.Z` comment), not a mutable tag — tags can be force-pushed to malicious code, as happened to `aquasecurity/trivy-action` in March 2026.
- **Tool versions are pinned** (Terraform, TFLint binary, TFLint azurerm ruleset) so runs are reproducible and not pulling `latest`.
- **`.github/dependabot.yml`** opens weekly PRs to bump the action SHAs and the Terraform lock file, so pinning stays current instead of going stale.
- **Least-privilege tokens**: the default workflow permission is `contents: read`; only the plan job is granted `id-token: write` (for OIDC). `persist-credentials: false` stops the checkout from leaving the `GITHUB_TOKEN` in `.git/config`.
- **Required action**: configure the `dev` GitHub Environment with **required reviewers**. `terraform plan` can execute code (external data sources, provider/module fetches), so on a `pull_request` the OIDC token must only be issued after a human approves the run — otherwise a malicious PR could run with your Azure credentials.

### Handling Trivy findings

`trivy config` runs in CI and fails the build on HIGH/CRITICAL misconfigurations. Real issues are fixed in the Terraform (RBAC, network policy, etc.). Where a control is environment-specific and cannot be hardcoded, it is recorded as an **accepted risk in `.trivyignore`** with a justification, owner, and expiry date (`exp:YYYY-MM-DD`) rather than disabling the scanner. The current exception is `AZU-0041` (public API server) — remove it once you set `api_server_authorized_ip_ranges` or enable a private cluster.

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
