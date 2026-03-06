# Architecture Decision Records

This directory contains Architecture Decision Records (ADRs) for the gitops repository. ADRs capture the key architectural decisions made during the development of our Kubernetes infrastructure, along with the context and consequences of each decision.

## ADR Index

| ADR | Title | Status |
|-----|-------|--------|
| [ADR-0001](0001-use-argocd-for-gitops.md) | Use ArgoCD as GitOps Operator | Accepted |
| [ADR-0002](0002-adopt-app-of-apps-pattern.md) | Adopt the App of Apps Pattern | Accepted |
| [ADR-0003](0003-two-branch-environment-strategy.md) | Two-Branch Environment Strategy | Accepted |
| [ADR-0004](0004-metallb-with-ebgp-for-load-balancing.md) | MetalLB with eBGP for Bare-Metal Load Balancing | Accepted |
| [ADR-0005](0005-ingress-nginx-as-daemonset.md) | Ingress-Nginx as DaemonSet with Static LoadBalancer IP | Accepted |
| [ADR-0006](0006-cert-manager-with-lets-encrypt.md) | Cert-Manager with Let's Encrypt for TLS | Accepted |
| [ADR-0007](0007-longhorn-for-persistent-storage.md) | Longhorn for Persistent Storage | Accepted |
| [ADR-0008](0008-kubeconform-ci-pipeline.md) | Kubeconform CI Pipeline for Manifest Validation | Accepted |
| [ADR-0009](0009-portfolio-helm-chart-deployment.md) | Portfolio as Local Helm Chart Deployment | Accepted |

## Creating a New ADR

1. Copy the [template](template.md) to a new file: `NNNN-short-title.md`
2. Use the next available number (zero-padded to 4 digits)
3. Fill in all sections: Status, Context, Decision, Consequences
4. Add the new ADR to the index table above
5. Submit via pull request for review
