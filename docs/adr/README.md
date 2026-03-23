# Architecture Decision Records

This directory contains Architecture Decision Records (ADRs) for the gitops repository. ADRs capture the key architectural decisions made during the development of our Kubernetes infrastructure, along with the context and consequences of each decision.

## ADR Index

| ADR | Title | Status |
|-----|-------|--------|
| [ADR-0001](0001-use-argocd-for-gitops.md) | Use ArgoCD as GitOps Operator | Accepted |
| [ADR-0002](0002-adopt-app-of-apps-pattern.md) | Adopt the App of Apps Pattern | Accepted |
| [ADR-0003](0003-two-branch-environment-strategy.md) | Two-Branch Environment Strategy | Accepted |
| [ADR-0004](0004-metallb-with-ebgp-for-load-balancing.md) | MetalLB with eBGP for Bare-Metal Load Balancing | Superseded by ADR-0016 |
| [ADR-0005](0005-ingress-nginx-as-daemonset.md) | Ingress-Nginx as DaemonSet with Static LoadBalancer IP | Accepted |
| [ADR-0006](0006-cert-manager-with-lets-encrypt.md) | Cert-Manager with Let's Encrypt for TLS | Accepted |
| [ADR-0007](0007-longhorn-for-persistent-storage.md) | Longhorn for Persistent Storage | Accepted |
| [ADR-0008](0008-kubeconform-ci-pipeline.md) | Kubeconform CI Pipeline for Manifest Validation | Accepted |
| [ADR-0009](0009-portfolio-helm-chart-deployment.md) | Portfolio as Local Helm Chart Deployment | Accepted |
| [ADR-0010](0010-filebrowser-for-file-sharing.md) | Filebrowser for File Sharing | Accepted |
| [ADR-0011](0011-argocd-image-updater.md) | ArgoCD Image Updater for Automated Image Promotion | Accepted |
| [ADR-0012](0012-portfolio-split-frontend-backend.md) | Split Portfolio into Separate Frontend and Backend Deployments | Accepted |
| [ADR-0013](0013-kube-prometheus-stack-monitoring.md) | Kube-Prometheus-Stack Monitoring | Accepted |
| [ADR-0014](0014-sealed-secrets-for-secret-management.md) | Sealed Secrets for Secret Management | Accepted |
| [ADR-0015](0015-kustomize-overlays-for-testing-environment.md) | Kustomize Overlays for Testing Environment | Accepted |
| [ADR-0016](0016-cilium-replaces-flannel-metallb-kube-proxy.md) | Cilium Replaces Flannel, MetalLB, and kube-proxy | Accepted |

## Creating a New ADR

1. Copy the [template](template.md) to a new file: `NNNN-short-title.md`
2. Use the next available number (zero-padded to 4 digits)
3. Fill in all sections: Status, Context, Decision, Consequences
4. Add the new ADR to the index table above
5. Submit via pull request for review
