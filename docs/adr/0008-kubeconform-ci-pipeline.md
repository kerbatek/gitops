# ADR-0008: Kubeconform CI Pipeline for Manifest Validation

## Status

Accepted

## Context

Pushing invalid Kubernetes manifests to the repository can break ArgoCD sync, causing downtime or failed deployments. We needed a CI gate to catch misconfigurations before they reach any branch.

Requirements:
- Validate plain YAML manifests against Kubernetes API schemas
- Support Custom Resource Definitions (CRDs) used by ArgoCD, cert-manager, MetalLB, Longhorn, etc.
- Lint and validate Helm chart templates before merging

## Decision

We will use a GitHub Actions CI pipeline (triggered on PRs to `main`) with three jobs:

1. **Validate manifests** (`validate`): Runs `kubeconform` (v0.6.7) against all YAML files in `k8s/`, validating against Kubernetes 1.32.0 schemas. Uses the Datree CRD catalog as a secondary schema source for custom resources.

2. **Lint Helm charts** (`helm-lint`): Runs `helm lint` on every chart in `charts/`.

3. **Validate rendered templates** (`helm-validate`): Renders Helm charts with `helm template` and pipes the output through kubeconform. Depends on `helm-lint` passing first.

## Consequences

- Invalid manifests and broken Helm charts are caught before merging to `main`
- CRD validation via the Datree catalog covers most popular Kubernetes extensions
- The pipeline runs only on PRs to `main`, not on the `testing` branch — experimental changes on `testing` bypass CI
- Kubeconform is fast and has no cluster dependency, making CI runs quick
- Schema validation catches structural issues but not semantic ones (e.g., a valid YAML that references a non-existent Secret)
- New CRDs not in the Datree catalog may produce false positives and require additional schema sources
