# ADR-0006: Cert-Manager with Let's Encrypt for TLS

## Status

Accepted

## Context

Services exposed via Ingress (see [ADR-0005](0005-ingress-nginx-as-daemonset.md)) need TLS certificates for HTTPS. Managing certificates manually — generating, renewing, and distributing them — is tedious and error-prone, especially as the number of Ingress resources grows.

We needed automated certificate lifecycle management that integrates with our Ingress controller and uses a trusted Certificate Authority.

## Decision

We will use cert-manager (chart version v1.16.3) with a Let's Encrypt production ClusterIssuer to automate TLS certificate provisioning and renewal.

Key configuration:
- **ClusterIssuer** (`letsencrypt-prod`): Defined in `k8s/infra/cert-manager/clusterissuer.yaml`, available cluster-wide for any namespace
- **Ingress annotation**: Services opt into automatic TLS by adding `cert-manager.io/cluster-issuer: letsencrypt-prod` to their Ingress resource
- **CRDs installed via Helm** (`crds.enabled: true`): Cert-manager CRDs are managed as part of the Helm release
- **Multi-source Application**: The ArgoCD Application uses two sources — the Helm chart for cert-manager itself, and the gitops repo for the ClusterIssuer config

## Consequences

- TLS certificates are automatically issued and renewed before expiry
- Any Ingress resource can request a certificate by adding a single annotation
- Let's Encrypt production certificates are trusted by all major browsers
- Cert-manager adds CRDs and controllers to the cluster that must be kept up to date
- Let's Encrypt rate limits apply — aggressive testing should use the staging issuer
- The ClusterIssuer is a separate resource managed alongside the Helm chart, requiring the multi-source pattern in ArgoCD
