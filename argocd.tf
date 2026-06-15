# -----------------------------------------------------------------------------
# Argo CD (GitOps) bootstrap
# -----------------------------------------------------------------------------
# Terraform installs Argo CD and (optionally) a single root "app-of-apps"
# Application. From that point on, all in-cluster applications are managed by
# Argo CD from your Git repository - Terraform does not manage app workloads.
#
# Separation of concerns:
#   Terraform  -> infrastructure + the GitOps engine (this file)
#   Argo CD    -> everything declared in var.gitops_repo_url
#
# Argo CD is kept internal (ClusterIP) and pinned to the on-demand user pool.
# Access it with: kubectl -n argocd port-forward svc/argocd-server 8080:443

locals {
  argocd_replicas = var.argocd_ha_enabled ? 2 : 1

  argocd_base_values = {
    # Keep Argo CD off the Spot pool; run it on stable on-demand nodes.
    global = {
      nodeSelector = { role = "general" }
    }
    "redis-ha" = {
      enabled = var.argocd_ha_enabled
    }
    controller = {
      replicas = 1
    }
    server = {
      replicas = local.argocd_replicas
      # Internal only. Expose deliberately via an ingress + SSO if required.
      service = {
        type = "ClusterIP"
      }
    }
    repoServer = {
      replicas = local.argocd_replicas
    }
    applicationSet = {
      replicas = local.argocd_replicas
    }
  }

  # Entra ID (Azure AD) OIDC SSO. clientSecret is referenced from the
  # argocd-secret ($oidc.azure.clientSecret) rather than inlined here.
  argocd_oidc_config = {
    name                   = "Azure"
    issuer                 = "https://login.microsoftonline.com/${data.azurerm_client_config.current.tenant_id}/v2.0"
    clientID               = var.argocd_oidc_client_id
    clientSecret           = "$oidc.azure.clientSecret"
    requestedIDTokenClaims = { groups = { essential = true } }
    requestedScopes        = ["openid", "profile", "email"]
  }

  argocd_sso_values = var.argocd_sso_enabled ? {
    configs = {
      cm = {
        url           = var.argocd_server_url
        "oidc.config" = yamlencode(local.argocd_oidc_config)
      }
      rbac = {
        "policy.default" = ""
        "policy.csv"     = join("\n", [for g in var.argocd_rbac_admin_groups : "g, ${g}, role:admin"])
      }
      # Only inject the secret key when provided; otherwise populate
      # oidc.azure.clientSecret in the argocd-secret out-of-band.
      secret = var.argocd_oidc_client_secret != "" ? {
        extra = { "oidc.azure.clientSecret" = var.argocd_oidc_client_secret }
      } : {}
    }
  } : {}

  argocd_values = merge(local.argocd_base_values, local.argocd_sso_values)
}

# Used to build the Entra ID OIDC issuer URL from the active tenant.
data "azurerm_client_config" "current" {}

resource "helm_release" "argocd" {
  count = var.enable_argocd ? 1 : 0

  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = var.argocd_namespace
  create_namespace = true

  values = [yamlencode(local.argocd_values)]

  # Needs cluster credentials (helm provider) and an untainted node pool to run
  # on, since the system pool is reserved.
  depends_on = [azurerm_kubernetes_cluster_node_pool.user]
}

# Root "app-of-apps" Application. Created only when a GitOps repo is provided.
# It points Argo CD at your repo; everything else is defined there in Git.
resource "helm_release" "argocd_apps" {
  count = var.enable_argocd && var.gitops_repo_url != "" ? 1 : 0

  name       = "argocd-apps"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = var.argocd_apps_chart_version
  namespace  = var.argocd_namespace

  values = [yamlencode({
    applications = {
      root = {
        namespace  = var.argocd_namespace
        project    = "default"
        finalizers = ["resources-finalizer.argocd.argoproj.io"]
        source = {
          repoURL        = var.gitops_repo_url
          targetRevision = var.gitops_target_revision
          path           = var.gitops_path
          directory      = { recurse = true }
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = var.argocd_namespace
        }
        syncPolicy = {
          automated   = { prune = true, selfHeal = true }
          syncOptions = ["CreateNamespace=true"]
        }
      }
    }
  })]

  depends_on = [helm_release.argocd]
}
