# ADR-0010: Filebrowser for File Sharing

## Status

Accepted

## Context

We needed a self-hosted file sharing solution accessible via the cluster's existing ingress and TLS infrastructure. Requirements were:
- Web-based UI for browsing, uploading, and downloading files
- Low resource footprint — this is a personal homelab, not a production file server
- Simple operational model with minimal dependencies
- Integration with Longhorn (PVCs), ingress-nginx, and cert-manager

Alternatives considered:
- **Nextcloud**: Full-featured personal cloud (Google Drive replacement). Rejected due to operational complexity — requires a separate database (PostgreSQL/MySQL), high memory usage, and significant configuration overhead for a single-user setup.
- **MinIO**: S3-compatible object storage. Rejected because MinIO relicensed from Apache 2.0 to AGPL-3.0 in 2021, and the operator/console carry additional commercial restrictions.
- **SeaweedFS / Garage**: Open-source S3-compatible alternatives. Not needed — S3 API compatibility is not a requirement; simple file access via a web UI is sufficient.

## Decision

We will deploy Filebrowser (`filebrowser/filebrowser:v2`) as a single-replica Deployment with raw Kubernetes manifests under `k8s/infra/filebrowser/`, managed by an ArgoCD Application sourced entirely from this repository.

Key configuration choices:
- **No upstream Helm chart**: Filebrowser has no official Helm chart. Raw manifests give full ownership with no dependency on third-party chart repositories.
- **Separate PVCs**: Two PVCs are used — `filebrowser-data` (20Gi, mounted at `/srv`) for files and `filebrowser-db` (1Gi, mounted at `/db`) for the SQLite database — to keep data and state independent.
- **ConfigMap for settings**: `/.filebrowser.json` is injected via a ConfigMap with `subPath`, avoiding volume mount conflicts at the container root.
- **`prune: true`**: Safe to enable unlike stateful components (e.g., Longhorn) — all resources are stateless except the PVCs, which survive ArgoCD pruning as they must be explicitly deleted.
- **TLS via cert-manager**: Served at `files.mrembiasz.pl` using the existing `letsencrypt-prod` ClusterIssuer.

## Consequences

- Lightweight file access is available at `https://files.mrembiasz.pl` with minimal cluster overhead (requests: 50m CPU, 64Mi RAM).
- Filebrowser is single-user-oriented by default; multi-user support exists but requires additional configuration.
- The floating image tag (`v2`) should be pinned to a specific digest after initial deployment to ensure reproducibility.
- Default credentials (`admin/admin`) must be changed immediately after first login. Credentials are stored in the SQLite database on the `filebrowser-db` PVC — not as a Kubernetes Secret — so they survive pod restarts but are not recoverable from git. If the PVC is lost, reset via `kubectl exec -- filebrowser users update admin --password <new>`.
- No S3 API or desktop sync client support — files are accessible only via the web UI or WebDAV (if enabled in settings).
