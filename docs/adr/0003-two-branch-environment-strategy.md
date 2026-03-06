# ADR-0003: Two-Branch Environment Strategy

## Status

Accepted

## Context

We need a way to test infrastructure changes before they reach production. Applying untested changes directly to the production cluster risks downtime and misconfiguration. At the same time, we want to keep the workflow simple — a full multi-cluster setup would add significant complexity.

The cluster serves as both staging and production on the same infrastructure, so environment separation must happen at the GitOps level.

## Decision

We will use a two-branch strategy for environment management:

- **`main` branch**: Production. The root `app-of-apps` targets this branch with automated sync (`selfHeal: true`, `prune: true`). Merging to `main` triggers immediate reconciliation.
- **`testing` branch**: Staging. The root `app-of-apps-testing` targets this branch without automated sync. Changes are applied manually after review.

Individual Application manifests use `targetRevision: main` to source their Helm charts and config from the production branch. The `testing` branch allows overriding these to test against feature branches when needed.

## Consequences

- Infrastructure changes can be validated on the `testing` branch before merging to `main`
- The `testing` environment doesn't auto-sync, allowing controlled manual promotion
- Both environments share the same cluster, so resource conflicts are possible (mitigated by separate namespaces)
- Branch divergence between `main` and `testing` requires periodic rebasing to stay in sync
- The PR workflow (`testing` -> `main`) provides a natural review gate for production changes
