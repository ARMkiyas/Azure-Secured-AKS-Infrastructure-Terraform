# GitOps repo scaffold (app-of-apps)

This folder is a **template for a separate Git repository** - the one you point
`gitops_repo_url` at. Copy its contents into that repo (or set `gitops_path`
to wherever you place the `apps/` directory).

## How it fits together

```
Terraform (this infra repo)                 GitOps repo (var.gitops_repo_url)
────────────────────────────                ─────────────────────────────────
installs Argo CD                            apps/
creates the root "app-of-apps"  ───watches──►  ├── podinfo.yaml   (child App)
Application pointing at apps/                   └── <your-apps>.yaml
                                            Argo CD syncs each child App
```

Terraform creates **one** root Application (via the `argocd-apps` chart) that
watches `apps/` with `directory.recurse = true`. Every Argo CD `Application`
manifest you drop into `apps/` is then deployed and continuously reconciled.
You ship changes by committing here - not by running Terraform.

## Layout

```
apps/
└── podinfo.yaml      # sample child Application (a demo workload)
```

## Add your own app

Create another `Application` in `apps/` pointing at your chart or manifests:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/my-app.git
    targetRevision: main
    path: deploy
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app
  syncPolicy:
    automated: { prune: true, selfHeal: true }
    syncOptions: ["CreateNamespace=true"]
```

## Scaling up

For many apps, environments, or clusters, prefer an **ApplicationSet** (generators)
over a static list of Applications - it removes per-app boilerplate and is the
recommended pattern beyond a handful of workloads.

## Scheduling notes

- Workloads land on the on-demand `user` pool by default.
- To run on the cheaper, interruptible Spot pool, add the toleration +
  `nodeSelector: { kubernetes.azure.com/scalesetpriority: spot }` (see the main
  README's compute section). Only do this for fault-tolerant workloads.
