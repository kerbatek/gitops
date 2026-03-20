# ADR-0014: Sealed Secrets for Secret Management

## Status

Accepted

## Context

Kubernetes Secrets cannot be committed to git safely — they are only base64-encoded, not encrypted. This creates a gap in the GitOps workflow: everything except secrets lives in git, meaning secrets must be managed out-of-band (manually applied to each cluster) and are not reproducible from the repository alone.

With a two-cluster setup (`testing` and `main` branches mapping to separate clusters), we need a solution that:
- Allows secrets to be stored encrypted in git alongside other manifests
- Works across both clusters without maintaining separate secret copies per branch
- Integrates with the existing ArgoCD App of Apps pattern

## Decision

We will deploy the Sealed Secrets controller (chart version 2.18.4) from `bitnami-labs/sealed-secrets` into `kube-system`.

Key configuration choices:
- **`fullnameOverride: sealed-secrets-controller`**: Sets a stable, predictable controller name that `kubeseal` expects by default, avoiding the need to pass `--controller-name` on every invocation
- **Deployed to `kube-system`**: Standard placement for cluster-wide infrastructure controllers
- **Shared encryption key across clusters**: The controller's private key is exported from the first cluster and imported into the second, allowing a single `SealedSecret` manifest to decrypt on both `testing` and `main` clusters

**Shared key workflow (one-time setup):**
```bash
# Export private key from first cluster
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > sealed-secrets-key.yaml

# Import into second cluster (after switching kubeconfig)
kubectl apply -f sealed-secrets-key.yaml -n kube-system
kubectl rollout restart deployment sealed-secrets-controller -n kube-system
```

**Sealing a secret:**
```bash
kubectl create secret generic <name> -n <namespace> \
  --from-literal=key=value \
  --dry-run=client -o yaml | \
  kubeseal --format yaml > k8s/infra/secrets/<namespace>/<name>-sealed.yaml
```

The resulting `SealedSecret` manifest is safe to commit to git, including public repositories.

**Secret storage structure:**

Sealed secrets are stored under `k8s/infra/secrets/` organised by namespace:
```
k8s/infra/secrets/
  monitoring/
    grafana-admin-sealed.yaml
```

A dedicated ArgoCD Application (`secrets`) watches this directory tree with `directory.recurse: true` and deploys all `SealedSecret` manifests. Each manifest explicitly sets its target namespace via `metadata.namespace`, so the app's `destination.namespace: default` is only used as a fallback for resources that omit a namespace (which these manifests do not).

## Consequences

- All secrets can now be stored encrypted in git — the repository becomes the single source of truth for the entire cluster state
- `sealed-secrets-key.yaml` becomes a critical credential; it must be stored securely outside git (e.g. password manager, offline backup) and never committed
- If the private key is lost and the cluster is rebuilt without restoring it, all `SealedSecrets` must be re-sealed — there is no recovery without the key
- The same sealed manifest works on both clusters, as long as the shared key has been imported
- Secrets are cluster-scoped by default — a `SealedSecret` sealed against one cluster's public key cannot be decrypted by a different cluster unless the key is explicitly shared
