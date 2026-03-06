# ADR-0001: Use ArgoCD as GitOps Operator

## Status

Accepted

## Context

We needed a way to manage Kubernetes resources declaratively, ensuring that the desired state of our cluster is defined in Git and automatically reconciled. Manual `kubectl apply` workflows are error-prone, lack audit trails, and don't scale as the number of managed resources grows.

Key requirements:
- Git as the single source of truth for cluster state
- Automatic drift detection and self-healing
- Support for Helm charts and plain YAML manifests
- A web UI for visibility into sync status
- Active community and ecosystem

## Decision

We will use ArgoCD (chart version 9.4.2 via `argoproj.github.io/argo-helm`) as our GitOps operator. ArgoCD watches this repository and continuously reconciles the cluster state to match the desired state defined here.

The reconciliation interval is set to 30 seconds (`timeout.reconciliation: 30s`) for fast feedback during development.

## Consequences

- All cluster changes go through Git, providing a full audit trail via commit history
- Drift from desired state is automatically detected and corrected (`selfHeal: true`)
- ArgoCD itself runs in-cluster, adding an operational component that must be maintained and monitored
- The ArgoCD web UI at `argocd.mrembiasz.pl` provides visibility into application sync status
- ArgoCD manages its own deployment (self-managing), which requires care during upgrades
