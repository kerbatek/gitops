# ADR-0003: Two-Branch Environment Strategy

## Status

Accepted

## Context

We need a way to test infrastructure and application changes before they reach production. Applying untested changes directly to the production cluster risks downtime and misconfiguration.

The testing environment runs on a separate Kubernetes cluster (VLAN 216, VM IDs 9000-9012) provisioned independently via Terraform, fully isolated from production (VLAN 215, VM IDs 8000-8014).

## Decision

We will use a two-branch strategy for environment management:

- **`main` branch**: Production. The root `app-of-apps` targets this branch with automated sync (`selfHeal: true`, `prune: true`). Merging to `main` triggers immediate reconciliation.
- **`testing` branch**: Staging. The root `app-of-apps-testing` targets this branch without automated sync. Changes are applied manually after review.

The promotion workflow is:

```
feature-branch → PR to testing → validate → merge testing → main
```

Changes are made on the `testing` branch, validated on the testing cluster, then `testing` is merged into `main`. Production's `app-of-apps` only reads `k8s/argocd/apps/` and ignores `k8s/overlays/`, so testing-specific overlay files merging to `main` have no effect on production.

Environment-specific configuration differences (network, hostnames, TLS) are managed via Kustomize overlays in `k8s/overlays/testing/` rather than inline modifications to shared files. See ADR-0015.

## Consequences

- Infrastructure changes can be validated on a fully isolated testing cluster before merging to `main`
- The `testing` environment doesn't auto-sync, allowing controlled manual promotion
- Two separate Terraform state files mean environments are independently managed — destroying testing has no impact on production
- `k8s/overlays/testing/` files accumulate on `main` over time but are inert — production never reads them
- Single PR flow: validate on testing, merge to main
