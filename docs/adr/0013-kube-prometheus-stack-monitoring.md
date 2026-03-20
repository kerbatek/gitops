# ADR-0013: kube-prometheus-stack for Cluster Monitoring

## Status

Accepted

## Context

As the cluster grows in workloads, we need visibility into resource usage, application health, and potential failures. Without a monitoring stack:
- There is no historical metrics data for troubleshooting
- No alerting on node or pod failures
- No dashboards for capacity planning

We needed a solution that:
- Integrates natively with Kubernetes (scrapes kubelet, API server, node metrics out of the box)
- Provides dashboards accessible via browser
- Fits into the existing ArgoCD GitOps workflow
- Persists metrics and alerting configuration across pod restarts

## Decision

We will deploy `kube-prometheus-stack` (chart version 82.10.4) from the `prometheus-community` Helm repository into the `monitoring` namespace.

Key configuration choices:
- **Grafana ingress**: Exposed at `grafana.mrembiasz.pl` via ingress-nginx with a Let's Encrypt TLS certificate managed by cert-manager; restricted to `10.0.0.0/8` via `nginx.ingress.kubernetes.io/whitelist-source-range`
- **Grafana admin credentials**: Loaded from a pre-existing `grafana-admin` Secret (managed by Sealed Secrets) via `grafana.admin.existingSecret` — prevents ArgoCD from regenerating a random password on every sync
- **Prometheus retention**: 15 days, backed by a 20Gi Longhorn PVC (`ReadWriteOncePod`)
- **Alertmanager storage**: 2Gi Longhorn PVC (`ReadWriteOncePod`) to persist silences and notification state across restarts
- **Prune disabled** (`prune: false`): Prevents accidental deletion of CRDs and PVCs during ArgoCD sync
- **ServerSideApply enabled**: Required to manage the large CRD schemas installed by the chart
- **`ignoreDifferences` for CRDs**: The `caBundle` field and CRD status are managed by the cluster and drift on every sync; ignoring them prevents perpetual out-of-sync state
- **`managedNamespaceMetadata`**: Sets `pod-security.kubernetes.io/enforce: privileged` on the `monitoring` namespace — required because node-exporter uses `hostNetwork`, `hostPID`, `hostPath` volumes, and `hostPort`, which are blocked by the `baseline` PodSecurity policy

## Consequences

- Full cluster observability: node, pod, and Kubernetes control-plane metrics are available immediately with pre-built Grafana dashboards
- Alertmanager is available for future alerting rules — no routing rules are configured initially
- The stack is resource-heavy; each component (Prometheus, Grafana, Alertmanager, node-exporter, kube-state-metrics) runs as a separate pod
- Prometheus and Alertmanager PVCs use `ReadWriteOncePod` — only one pod cluster-wide can hold the mount at a time, preventing split-brain writes during rolling restarts. Longhorn's 3x replication means the volume follows the pod to any node.
- CRDs installed by the chart (ServiceMonitor, PrometheusRule, etc.) become available cluster-wide, allowing future workloads to register their own scrape targets declaratively
- Chart version must be pinned and manually bumped; upgrades may require CRD migration steps
