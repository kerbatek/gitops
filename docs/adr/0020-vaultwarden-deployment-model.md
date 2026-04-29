# ADR-0020: Vaultwarden Deployment Model

## Status

Accepted

## Context

We need to run Vaultwarden in this cluster using the existing GitOps, ingress, TLS, storage, and secret-management patterns already established in this repository.

The deployment is intended for a small personal installation rather than a horizontally scaled service. That makes operational simplicity more important than multi-node application-level redundancy. The cluster already standardizes on:

- ArgoCD Applications managed from git
- raw Kubernetes manifests for smaller self-hosted services
- Longhorn for persistent volumes
- ingress-nginx and cert-manager for public HTTPS endpoints
- Sealed Secrets for encrypted secret material in git

## Decision

We will deploy Vaultwarden as a single-replica application managed entirely from this repository.

Key deployment choices:

- **Raw manifests in-repo**: Vaultwarden is defined under `k8s/infra/vaultwarden/` and attached to ArgoCD through `k8s/argocd/apps/vaultwarden.yaml`.
- **Single replica with `Recreate`**: The application runs as one `Deployment` replica and uses a `Recreate` strategy to avoid concurrent writers against the same SQLite-backed data directory.
- **SQLite on Longhorn**: Persistent state is stored on a Longhorn-backed PVC mounted at `/data`. This includes the SQLite database and uploaded attachments.
- **Public ingress with cluster TLS**: Vaultwarden is exposed at `vault.mrembiasz.pl` through `ingress-nginx`, with certificates issued by the existing `letsencrypt-prod` ClusterIssuer.
- **Configuration via Sealed Secret**: Runtime values such as `ADMIN_TOKEN`, `DOMAIN`, `ROCKET_PORT`, `SIGNUPS_ALLOWED`, and `WEBSOCKET_ENABLED` are stored in a Kubernetes `Secret` generated from a Sealed Secret committed to git.
- **Closed signup model**: Public signups are disabled. Administrative access is provided through the Vaultwarden admin panel token, and user creation is controlled explicitly rather than leaving self-registration open.
- **Pinned image version**: The container image is pinned to a specific Vaultwarden release instead of following a floating tag.

## Consequences

- The deployment matches the repository's existing operational model and is straightforward to reason about in GitOps.
- Vaultwarden can be reached through the cluster's normal public HTTPS path without introducing a separate access pattern or proxy layer.
- Operational state is concentrated in the `/data` volume, so backup and restore of that volume are the critical recovery path.
- The application is intentionally single-instance. This is acceptable for the current scale, but it is not an HA deployment model.
- SQLite keeps the deployment simple, but it also makes shared-writer or multi-replica scaling inappropriate without changing the storage model.
- The admin token becomes a high-sensitivity operational secret. It must be generated outside git, sealed before commit, and handled as a privileged credential for the `/admin` endpoint.
- Attachment usage and database growth consume Longhorn capacity directly, so Vaultwarden storage must be sized and monitored like other persistent services in the cluster.
