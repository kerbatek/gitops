# GitOps

Kubernetes GitOps repository managed by ArgoCD. Defines the desired state of the cluster — infrastructure, networking, storage, and application workloads — as code.

## Repository Structure

```
k8s/
  argocd/
    app-of-apps.yaml            # Root Application (production, main branch)
    app-of-apps-testing.yaml    # Root Application (staging, testing branch)
    apps/                       # Child Application definitions
      argocd.yaml               #   ArgoCD (self-managing)
      cert-manager.yaml         #   TLS certificate automation
      ingress-nginx.yaml        #   Ingress controller
      longhorn.yaml             #   Distributed block storage
      metallb.yaml              #   Bare-metal load balancer
      portfolio.yaml            #   Portfolio application
  infra/
    cert-manager/               # ClusterIssuer config
    longhorn/                   # Longhorn namespace config
    metallb/                    # MetalLB IP pool and BGP peer config
charts/
  portfolio/                    # Local Helm chart for portfolio app
.github/
  workflows/
    ci.yml                      # Kubeconform + Helm lint/validate
docs/
  adr/                          # Architecture Decision Records
```

## How It Works

This repo uses the **App of Apps** pattern. A single root ArgoCD Application watches the `k8s/argocd/apps/` directory and manages all child Applications. Each child Application points to either an upstream Helm chart or a local chart in `charts/`.

**Branching strategy:**
- `main` — Production. Auto-synced by ArgoCD with self-heal and prune.
- `testing` — Staging. Manual sync for validating changes before promotion.

## Stack

| Component | Purpose | Version |
|-----------|---------|---------|
| ArgoCD | GitOps operator | 9.4.2 (Helm chart) |
| MetalLB | Bare-metal LoadBalancer (eBGP) | 0.15.3 |
| ingress-nginx | Ingress controller (DaemonSet) | 4.11.3 |
| cert-manager | TLS via Let's Encrypt | v1.16.3 |
| Longhorn | Distributed block storage | 1.7.2 |

## Prerequisites

- Kubernetes cluster (v1.32+)
- ArgoCD installed in the `argocd` namespace
- Network router configured for BGP peering with MetalLB
- DNS records pointing to the ingress LoadBalancer IP (`10.0.216.1`)

## Documentation

- [Architecture Decision Records](docs/adr/README.md) — Why we made the decisions we made
