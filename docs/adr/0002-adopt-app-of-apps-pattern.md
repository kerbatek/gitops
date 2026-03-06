# ADR-0002: Adopt the App of Apps Pattern

## Status

Accepted

## Context

As the number of ArgoCD Applications grows (MetalLB, ingress-nginx, cert-manager, Longhorn, etc.), managing them individually becomes cumbersome. Each Application resource needs to be applied manually or through a separate mechanism, defeating the purpose of GitOps.

We needed a way to declaratively manage the set of Applications themselves, so that adding a new service to the cluster is as simple as adding a YAML file to a directory.

## Decision

We will use ArgoCD's App of Apps pattern. A single root Application (`app-of-apps`) points to the `k8s/argocd/apps/` directory and automatically discovers and manages all child Application resources within it.

- **Production root app** (`app-of-apps`): targets `main` branch, with automated sync, self-heal, and prune enabled
- **Testing root app** (`app-of-apps-testing`): targets `testing` branch, without automated sync (manual promotion)

Adding a new service means creating a new Application YAML in `k8s/argocd/apps/` — ArgoCD picks it up automatically.

## Consequences

- New services are onboarded by adding a single file to `k8s/argocd/apps/`
- Removing a file (with `prune: true` on the root app) cleanly removes the service from the cluster
- All Application definitions are version-controlled and reviewable via PRs
- The root app is a single point of failure — if it breaks, no child apps sync
- The pattern creates a two-level hierarchy, which is simple but may need restructuring if the number of apps grows significantly (e.g., ApplicationSets)
