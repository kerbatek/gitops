# ADR-0019: Portfolio Chart Sourced from the Portfolio Repository

## Status

Accepted

## Context

The original `portfolio` deployment model in this repository used a local Helm chart (`charts/portfolio`) and later relied on ArgoCD Image Updater to write image tag changes back into `gitops` (see [ADR-0009](0009-portfolio-helm-chart-deployment.md) and [ADR-0011](0011-argocd-image-updater.md)).

That model was acceptable for the first version of the application, but it became a poor ownership boundary as the project grew:

- Application code, Dockerfiles, and CI lived in the `portfolio` repository, while the chart that defined the deployable topology lived in `gitops`
- Image tag promotion happened outside the application repository, which weakened the coupling between an application revision and the deployment definition that should run it
- Testing and production needed clearer branch-to-environment mapping so deployment changes could be validated on `testing` before promotion to `main`

At the same time, this repository still needs to own the cluster-facing control plane:

- Argo CD `Application` resources
- Environment-specific overrides such as domains, replica counts, and TLS settings
- Shared platform services and secrets

## Decision

For `portfolio`, this repository will source the Helm chart from the `portfolio` repository instead of storing a local chart.

The resulting split is:

- The `portfolio` repository owns `deploy/helm/portfolio`, image references, and the topology of application-owned services
- The `gitops` repository owns the Argo CD `Application`, environment-specific Helm overrides, sync policy, and cluster/platform resources

Branch mapping is explicit:

- Production tracks `portfolio/main`
- Testing tracks `portfolio/testing`

The release trigger is also explicit:

- GitHub Actions in the `portfolio` repository builds images and commits chart tag updates back to the branch that triggered the workflow
- Argo CD detects the new Git revision on the tracked branch and re-renders the chart from `deploy/helm/portfolio`

This ADR supersedes the `portfolio`-specific parts of [ADR-0009](0009-portfolio-helm-chart-deployment.md) and [ADR-0011](0011-argocd-image-updater.md).

## Consequences

- Application version, image tag, and chart definition now move together in the application repository
- `gitops` keeps a cleaner role as environment orchestrator rather than application release repository
- Testing can validate `portfolio/testing` end to end before the same change is promoted to `main`
- The Argo CD configuration is slightly more complex because the Application sources manifests from a different repository than the one that defines the Application object
- The old local chart and `portfolio` Image Updater configuration are removed from this repository once production cutover is complete
