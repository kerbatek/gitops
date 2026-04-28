# Vaultwarden Deployment Design

Date: 2026-04-28
Status: Proposed

## Context

The cluster is managed from this repository with Argo CD using the app-of-apps pattern. Shared platform services are defined as child Argo CD Applications under `k8s/argocd/apps/`, with service-specific manifests stored under `k8s/infra/`.

The goal is to add Vaultwarden as a lightweight, self-hosted Bitwarden-compatible password manager for a small deployment. The service will be publicly exposed through the cluster's existing ingress and TLS stack.

Requirements:

- Public HTTPS access at `vault.mrembiasz.pl`
- Small operational footprint suitable for a single user or household-scale deployment
- Persistent storage on the existing Longhorn-backed default StorageClass
- GitOps management through Argo CD
- No open self-registration
- No SMTP dependency on day one

## Decision

Vaultwarden will be deployed from raw Kubernetes manifests stored in this repository, following the same operational pattern as `filebrowser`.

The deployment will use:

- A dedicated Argo CD child Application at `k8s/argocd/apps/vaultwarden.yaml`
- Service manifests under `k8s/infra/vaultwarden/`
- A single replica Vaultwarden `Deployment`
- SQLite stored on a Longhorn-backed PVC mounted at `/data`
- Public ingress on `vault.mrembiasz.pl` through `ingress-nginx`
- TLS certificates issued by the existing `letsencrypt-prod` `ClusterIssuer`
- Runtime configuration provided by a Sealed Secret

This approach keeps the dependency surface small and aligns with the repo's existing pattern for lightweight, repo-managed services.

## Rejected Alternatives

### Third-party Helm chart

Using a community Helm chart would reduce the amount of manifest YAML in this repo, but it adds another abstraction layer and external chart dependency for a security-sensitive service. That is a worse fit than direct manifests for this cluster.

### External database on day one

Running Vaultwarden against PostgreSQL would add operational complexity without clear value for a small single-instance deployment. SQLite is sufficient for the intended scale and keeps the stack simpler.

## Architecture

### Argo CD Application

Add `k8s/argocd/apps/vaultwarden.yaml` as a standard child application:

- `destination.namespace: vaultwarden`
- `syncPolicy.automated.selfHeal: true`
- `syncPolicy.automated.prune: true`
- `syncOptions: CreateNamespace=true`

This matches the existing `filebrowser` application pattern.

### Workload

Vaultwarden will run as a single-replica `Deployment` in the `vaultwarden` namespace.

Key runtime choices:

- `strategy.type: Recreate`
- one container using a pinned `vaultwarden/server` image tag
- a single PVC mounted at `/data`
- modest CPU and memory requests and limits
- readiness and liveness probes on the HTTP endpoint

`Recreate` is appropriate because SQLite is file-based and the intended topology is one replica only.

### Storage

Provision one PVC using the cluster's default Longhorn StorageClass. The volume mounted at `/data` will store:

- the SQLite database
- attachment data
- other Vaultwarden state persisted by the container

No separate database service will be introduced.

### Networking

Expose Vaultwarden through a ClusterIP `Service` and an `Ingress` resource.

Ingress configuration:

- host: `vault.mrembiasz.pl`
- ingress class: `nginx`
- TLS secret managed by cert-manager
- annotations for larger request bodies to support attachment uploads

TLS will terminate at ingress, and the service will run plain HTTP inside the cluster. This is consistent with the existing ingress model in the repo.

## Security Configuration

Runtime configuration will be supplied through a Sealed Secret stored under `k8s/infra/secrets/vaultwarden/`.

Expected environment variables:

- `DOMAIN=https://vault.mrembiasz.pl`
- `SIGNUPS_ALLOWED=false`
- `ADMIN_TOKEN=<strong random token>`
- `WEBSOCKET_ENABLED=true`
- `ROCKET_PORT=80`

Optional settings such as SMTP will be omitted initially.

### Registration model

Open self-registration will be disabled. User creation and administration will happen through the Vaultwarden admin interface using `ADMIN_TOKEN`.

### Secrets handling

No plaintext credentials or bootstrap values will be committed to git. The Sealed Secret will be the only committed representation of the runtime secret material.

## Operational Concerns

### Backups

The `/data` PVC is the critical state for this service. The operational design assumes Longhorn recurring snapshots or backups are configured for the volume, with a documented restore path outside this spec.

This is required because losing `/data` means losing:

- the SQLite database
- attachment files
- application state stored by Vaultwarden

### Upgrades

The container image should be pinned to a specific version rather than a floating tag. Upgrades should happen by explicitly changing the image version in git and allowing Argo CD to roll out the new pod.

### Resource profile

Vaultwarden is expected to be lightweight. Initial requests and limits should stay conservative and can be adjusted after observing actual usage.

## Repository Changes

Expected files:

- `k8s/argocd/apps/vaultwarden.yaml`
- `k8s/infra/vaultwarden/kustomization.yaml`
- `k8s/infra/vaultwarden/deployment.yaml`
- `k8s/infra/vaultwarden/service.yaml`
- `k8s/infra/vaultwarden/ingress.yaml`
- `k8s/infra/vaultwarden/pvc.yaml`
- `k8s/infra/secrets/vaultwarden/vaultwarden-env-sealed.yaml`

No testing overlay is required on day one unless Vaultwarden is also meant to run in the testing cluster.

## Out Of Scope

The following are intentionally excluded from the initial deployment:

- SMTP and email-based invitations or password reset
- PostgreSQL
- multi-replica Vaultwarden
- SSO integration
- separate backup automation manifests in this repo

## Rollout Notes

Recommended rollout sequence:

1. Add the Sealed Secret for Vaultwarden runtime configuration.
2. Add the PVC, Deployment, Service, and Ingress manifests under `k8s/infra/vaultwarden/`.
3. Add the child Argo CD Application under `k8s/argocd/apps/`.
4. Let Argo CD create the namespace and sync the application.
5. Verify TLS issuance, ingress reachability, and successful login using an admin-created account.

## Success Criteria

The design is successful when:

- `https://vault.mrembiasz.pl` serves Vaultwarden over a valid certificate
- the application persists state across pod restarts
- open registration is disabled
- runtime secrets are stored only as a Sealed Secret in git
- the deployment is fully managed through Argo CD from this repository
