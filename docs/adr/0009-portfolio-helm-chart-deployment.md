# ADR-0009: Portfolio as Local Helm Chart Deployment

## Status

Superseded by [ADR-0019](0019-portfolio-chart-sourced-from-portfolio-repo.md) for chart ownership and promotion flow
(image update mechanism was previously superseded by [ADR-0011](0011-argocd-image-updater.md); single-container architecture was superseded by [ADR-0012](0012-portfolio-split-frontend-backend.md))

## Context

The portfolio application is the first user-facing workload deployed through this GitOps repository. Unlike infrastructure components (MetalLB, Longhorn, etc.) which use upstream Helm charts, the portfolio app is custom and needs its own deployment configuration.

We needed to decide how to package and deploy application workloads:
- Plain YAML manifests in the gitops repo
- A local Helm chart in the gitops repo
- A separate Helm chart repository

## Decision

We will deploy the portfolio application as a **local Helm chart** stored in `charts/portfolio/` within this repository.

This ADR captures the initial deployment model. The current model is defined by [ADR-0019](0019-portfolio-chart-sourced-from-portfolio-repo.md), which moves chart ownership into the `portfolio` repository while keeping the Argo CD `Application` and environment overrides in `gitops`.

Key configuration:
- **Chart location**: `charts/portfolio/` contains `Chart.yaml`, `values.yaml`, and templates for Deployment, Service, and Ingress
- **ArgoCD Application**: Sources the chart from this repo (`path: charts/portfolio`) with Helm values overrides (`replicas: 3`, `image.tag: latest`)
- **Automated image updates**: An external process bumps the `image.tag` value on the `main` branch (visible in commits `0a60ab8` → `7e6a4a3`), triggering ArgoCD sync
- **Namespace isolation**: Deployed to a dedicated `portfolio` namespace with `CreateNamespace=true`
- **Full sync policy**: Automated sync with self-heal and prune enabled

## Consequences

- Application deployment configuration lives alongside infrastructure in one repo (monorepo approach)
- Helm templating provides flexibility for environment-specific overrides via `valuesObject`
- The CI pipeline validates the chart structure and rendered templates before merge
- Image tag updates on `main` trigger automatic redeployment — the external image bumper acts as a simple CD pipeline
- Storing application charts in the gitops repo couples application and infrastructure lifecycles — may need to separate as the number of applications grows
- The `latest` tag in `values.yaml` is overridden by the ArgoCD Application's `valuesObject`, keeping the chart generic
- This repository no longer uses this model for `portfolio`; it remains as historical context for the first iteration of the deployment
