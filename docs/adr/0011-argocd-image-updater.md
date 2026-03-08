# ADR-0011: ArgoCD Image Updater for Automated Image Promotion

## Status

Accepted

## Context

Application image tags were previously updated via a push model: each application repository's CI pipeline committed tag changes directly to this gitops repo (e.g., `chore: bump portfolio image to sha-XXXXX`). This approach has scaling limitations:

- **Credential sprawl**: Every application repo needs write access (PAT) to the gitops repo. More repos increase the blast radius of a token leak.
- **Merge conflicts**: Concurrent CI runs from multiple app repos race to push to the same branch, causing `non-fast-forward` errors.
- **Tight coupling**: Each app CI must know the exact file path and YAML structure in the gitops repo. Refactoring the gitops layout requires updating every app repo's workflow.
- **Noisy history**: The `main` branch fills with `chore: bump` commits, obscuring real infrastructure changes.

Additionally, the App of Apps pattern (ADR-0002) with `selfHeal: true` on the root Application means any in-cluster-only image override (e.g., from an Image Updater without write-back) would be reverted by self-heal, since the root app enforces that child Application CRs match git.

## Decision

We will deploy **ArgoCD Image Updater** (v1.1.0, chart v1.1.1) as a pull-based image promotion controller with **git write-back**.

Key configuration:

- **Deployment**: Helm chart `argocd-image-updater` from the argo-helm repo, deployed to the `argocd` namespace as a child Application
- **Registry**: GHCR (`ghcr.io`) with credentials from `pullsecret:argocd/ghcr-creds` (docker-registry type secret, classic PAT with `read:packages` scope)
- **Configuration model**: CRD-based — each tracked application is defined via an `ImageUpdater` custom resource in `k8s/infra/argocd-image-updater/`, deployed as a second source in the Image Updater's multi-source Application
- **Update strategy**: `newest-build` — selects the most recently built image tag matching the allow-tags pattern
- **Tag filter**: `regexp:^sha-[a-f0-9]+$` — matches the existing `sha-XXXXXXX` tagging convention
- **Write-back method**: `git:secret:argocd/git-creds` — commits a `.argocd-source-<app>.yaml` parameter override file to the chart directory, preserving git as the single source of truth
- **Helm integration**: `manifestTargets.helm` maps image name and tag to Helm values (`image.repository`, `image.tag`)

Required secrets (created manually, not stored in git):

- `argocd/ghcr-creds`: `kubernetes.io/dockerconfigjson` type secret (created via `kubectl create secret docker-registry`), classic GitHub PAT with `read:packages` scope. Fine-grained PATs do not work with GHCR's Docker v2 registry API.
- `argocd/git-creds`: Opaque secret with `username` and `password` keys, classic GitHub PAT with `repo` scope. Fine-grained PATs do not work with Git HTTP push authentication.

## Consequences

- Application repos no longer need write access to the gitops repo — they only push images to GHCR
- Adding a new app to automated image promotion requires only a new `ImageUpdater` CR in `k8s/infra/argocd-image-updater/`
- Git remains the single source of truth — write-back commits `.argocd-source-<app>.yaml` files that ArgoCD reads as Helm parameter overrides
- Compatible with App of Apps self-heal — no `ignoreDifferences` workarounds needed
- Introduces a new in-cluster component (Image Updater) that requires maintenance and monitoring
- Two secrets must be managed out-of-band (`ghcr-creds`, `git-creds`)
- Replaces the push-model image bumping described in ADR-0009; the `chore: bump` workflow in app repos should be removed once Image Updater is operational
