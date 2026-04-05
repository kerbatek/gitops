# GitOps

GitOps repository for a Kubernetes homelab cluster managed with Argo CD. The repo defines cluster infrastructure, shared platform services, sealed secrets, and application workloads as declarative manifests.

## Overview

This repository uses the Argo CD App of Apps pattern:

- Production entrypoint: `k8s/argocd/app-of-apps.yaml`
- Testing entrypoint: `k8s/overlays/testing/app-of-apps-testing.yaml`

Production tracks the `main` branch and syncs the child applications from `k8s/argocd/apps/`.
Testing tracks the `testing` branch and builds the same application set through Kustomize overlays in `k8s/overlays/testing/apps/`.

That setup keeps the base application definitions shared while allowing testing-specific overrides for domains, IPs, branch revisions, and selected infra manifests.
Both environments now run on routed per-node `/31` links with Cilium BGP, while keeping VLANs, ASNs, and API VIPs disjoint between testing and production.

## Repository Layout

```text
charts/
  portfolio/                  # Local Helm chart for the portfolio app

docs/
  adr/                        # Architecture Decision Records
  runbooks/                   # Operational runbooks

k8s/
  argocd/
    app-of-apps.yaml          # Production root Argo CD Application
    apps/                     # Base child Applications
  infra/
    argocd-image-updater/     # Image updater config
    cert-manager/             # ClusterIssuer manifests
    cilium/                   # Cilium BGP and DNS-related manifests
    filebrowser/              # Filebrowser manifests
    longhorn/                 # Longhorn namespace config
    secrets/                  # Sealed secrets for Argo CD and monitoring
  overlays/
    testing/
      app-of-apps-testing.yaml
      apps/                   # Kustomize overlay for testing Applications
      infra/                  # Testing-specific infra overlays
```

## Managed Components

The current Argo CD application set includes:

- `argocd`: self-managed Argo CD installation
- `argocd-image-updater`: automated image tag updates for the portfolio app
- `cert-manager`: Let's Encrypt certificate management
- `cilium`: CNI, kube-proxy replacement, BGP control plane, and LoadBalancer IP management
- `filebrowser`: web-based file access service
- `ingress-nginx`: ingress controller
- `kube-prometheus-stack`: Prometheus, Alertmanager, and Grafana
- `longhorn`: persistent block storage
- `portfolio`: local Helm chart deploying frontend and backend workloads
- `sealed-secrets`: Bitnami Sealed Secrets controller
- `secrets`: sealed secret manifests applied from this repo

## Environments

### Production

- Branch: `main`
- Root app: `k8s/argocd/app-of-apps.yaml`
- Child app source path: `k8s/argocd/apps`
- Sync policy: automated with self-heal and prune on the root application
- Cluster shape: 3 control planes and 3 workers
- API access model: kubePrism on `localhost:7445` for node-local clients, Cilium-managed VIP `10.0.217.5/32` for external clients
- Networking model: per-node `/31`, per-node VLAN, per-node eBGP peer, and Cilium `routingMode: native` with `autoDirectNodeRoutes: false`

### Testing

- Branch: `testing`
- Root app: `k8s/overlays/testing/app-of-apps-testing.yaml`
- Child app source path: `k8s/overlays/testing/apps`
- Overlay model: reuses base applications and patches branch revisions, domains, ingress IPs, and selected infra paths
- API access model: kubePrism on `localhost:7445` for node-local clients, Cilium-managed VIP `10.0.216.5/32` for external clients
- Networking model: mirrors the routed per-node `/31` production design with non-overlapping VLANs and ASNs

Notable testing overrides currently include:

- Argo CD domain changed to `argocd.testing.mrembiasz.pl`
- Grafana domain changed to `grafana.testing.mrembiasz.pl`
- Portfolio ingress changed to `testing.mrembiasz.pl`
- Different Cilium API endpoint, pod CIDR, and infra path
- Different ingress LoadBalancer IP
- Different per-node VLAN range (`2161-2166`) and ASN range (`65101-65106`) from production (`2171-2176`, `65201-65206`)

## Portfolio Application

The portfolio workload is deployed from the local Helm chart in `charts/portfolio`.

- Separate `frontend` and `backend` deployments
- Images pulled from `ghcr.io/kerbatek/portfolio-frontend` and `ghcr.io/kerbatek/portfolio-backend`
- Ingress managed through `ingress-nginx`
- Image tags can be updated automatically by Argo CD Image Updater via `k8s/infra/argocd-image-updater/portfolio.yaml`

## Documentation

- [ADRs](docs/adr/README.md) explain the architectural decisions behind the platform
