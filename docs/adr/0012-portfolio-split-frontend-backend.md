# ADR-0012: Split Portfolio into Separate Frontend and Backend Deployments

## Status

Accepted (chart ownership and promotion flow superseded by [ADR-0019](0019-portfolio-chart-sourced-from-portfolio-repo.md))

## Context

The portfolio application was initially deployed as a single container (ADR-0009). This worked when the site was a Hugo static site served by nginx. After migrating to a SPA architecture, the application now consists of two distinct components:

- **Frontend**: A React/Vite SPA served by nginx, handling all UI rendering
- **Backend**: A Go/Gin API server exposing `/api/*` endpoints for content (posts, pages, tags)

The previous single-container model could have been preserved by building one image with Go serving the static frontend files. However, this would obscure the underlying architecture and reduce the opportunities to demonstrate multi-service deployment patterns.

## Decision

We will split the portfolio Helm chart into two independent Deployments, Services, and image references.

Key configuration:

- **Two Deployments**: `portfolio-frontend` and `portfolio-backend`, each with their own replica count, resource limits, and health check paths (`/` and `/api/posts` respectively)
- **Two Services**: frontend on port 80, backend on port 8080, both ClusterIP
- **Ingress routing**: A single Ingress routes `/api` (Prefix) to the backend and `/` (Prefix) to the frontend; `/api` is listed first so nginx evaluates it before the catch-all
- **`_helpers.tpl`**: A `portfolio.deployment` and `portfolio.service` named template centralise the repeated Deployment and Service structure; each component passes its values section and probe path as parameters, keeping `deployment.yaml` and `service.yaml` to 4 lines each
- **Two image repositories in the chart**: `ghcr.io/kerbatek/portfolio-frontend` and `ghcr.io/kerbatek/portfolio-backend`, with a shared branch-coupled tag driven from the `portfolio` repository's release flow
- **values.yaml structure**: Flat single-image structure replaced with `frontend:` and `backend:` top-level sections, each containing `image`, `replicas`, `containerPort`, and `resources`, plus a shared `global.imageTag`
- **ArgoCD Application `valuesObject`**: Overrides only environment-specific settings such as replicas, ingress hosts, and TLS details; image tags are now owned by the chart source repository

## Consequences

- Frontend and backend can be scaled independently — useful if the API becomes a bottleneck separately from static file serving
- The Helm chart expresses a clearer multi-service application boundary while the branch-coupled release flow keeps image and chart revisions together
- The `_helpers.tpl` abstraction eliminates ~75 lines of duplicated YAML; adding a third component requires only a new `include` call and values section
- Image tags must not be hardcoded in the Application `valuesObject` — doing so overrides the application repository's chart state
- The Helm chart is more complex but more representative of real multi-service deployments
- Both components share the same namespace, TLS certificate, and ingress, keeping operational overhead low
