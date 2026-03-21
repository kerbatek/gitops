# ADR-0015: Kustomize Overlays for Testing Environment Configuration

## Status

Accepted

## Context

The testing cluster requires environment-specific configuration that differs from production: different network ranges (VLAN 216, `10.0.216.0/24`), separate MetalLB IP pool (`10.1.129.0/26`), different BGP ASN (64515), testing subdomains (`*.testing.mrembiasz.pl`), and no TLS (internal-only hostnames are not publicly routable, so ACME HTTP-01 challenges fail).

An initial approach of modifying shared files directly on the `testing` branch (inline overrides) was rejected because feature PRs touch the same files, causing merge conflicts every time `main` is merged into `testing`.

## Decision

All testing-specific configuration lives in `k8s/overlays/testing/`, which only exists on the `testing` branch and is never merged to `main`:

```
k8s/overlays/testing/
├── app-of-apps-testing.yaml          # Bootstrap manifest (applied manually)
├── apps/
│   ├── kustomization.yaml            # References base apps + applies patches
│   └── patches/                      # Partial Application manifests (merge patches)
│       ├── argocd.yaml               # Hostname, TLS, kustomize.buildOptions
│       ├── ingress-nginx.yaml        # LoadBalancer IP
│       ├── kube-prometheus-stack.yaml # Hostname, TLS
│       ├── metallb.yaml              # BGP peer, ASN, IP pool (via infra overlay)
│       ├── filebrowser.yaml          # Hostname, TLS (via infra overlay)
│       └── portfolio.yaml            # Hostname, TLS
└── infra/
    ├── metallb/kustomization.yaml    # JSON 6902 patches: peerAddress, myASN, pool
    └── filebrowser/kustomization.yaml # JSON 6902 patches: hostname, TLS removal
```

`app-of-apps-testing.yaml` points ArgoCD at `k8s/overlays/testing/apps/` instead of `k8s/argocd/apps/`, causing ArgoCD to render the Kustomize overlay before deploying any Application resources.

ArgoCD requires `--load-restrictor LoadRestrictionsNone` to allow Kustomize to reference resources from parent directories (`../../../argocd/apps/`). This is configured in the ArgoCD Helm values via `patches/argocd.yaml` and patched into `argocd-cm` manually during bootstrap before the first sync.

Patch files are excluded from kubeconform CI validation as they are intentionally incomplete (partial manifests without required fields like `destination` and `project`).

## Consequences

- Shared files (`k8s/argocd/apps/`, `k8s/infra/`) are identical on both branches — no merge conflicts when promoting testing → main
- Overlay files accumulate on `main` over time but are inert — production's `app-of-apps` never reads `k8s/overlays/`
- All testing differences are visible in one place (`k8s/overlays/testing/`)
- Adding a new app requires adding it to `k8s/overlays/testing/apps/kustomization.yaml` on the `testing` branch, in addition to the base app definition on `main`
- The `--load-restrictor LoadRestrictionsNone` flag must be bootstrapped manually before the first ArgoCD sync on a new testing cluster
- `kustomization.yaml` files and patch files must be excluded from kubeconform validation
