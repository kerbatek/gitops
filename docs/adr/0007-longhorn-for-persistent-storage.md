# ADR-0007: Longhorn for Persistent Storage

## Status

Accepted

## Context

Stateful applications on Kubernetes require persistent volumes. On bare-metal clusters, there is no cloud-provided storage class. We needed a distributed storage solution that:
- Provides a default StorageClass for dynamic PV provisioning
- Replicates data across nodes for resilience
- Works with our existing bare-metal infrastructure without external storage appliances

## Decision

We will use Longhorn (chart version 1.7.2) as our distributed block storage system.

Key configuration choices:
- **Default StorageClass**: Longhorn is configured as the cluster's default storage class (`defaultClass: true`)
- **3x replication**: Both the default replica count and persistence replica count are set to 3, matching our node count for maximum resilience
- **Storage overprovisioning**: Set to 200% to allow flexible scheduling; minimal available threshold at 10%
- **CSI sidecar replicas**: Set to 2 each (attacher, provisioner, resizer, snapshotter) for HA
- **Pre-upgrade checker disabled** (`jobEnabled: false`): Removed after it caused sync issues in ArgoCD (commit `bf46d3a`)
- **ServerSideApply enabled**: Required to handle CRD field ownership conflicts
- **`ignoreDifferences` for CRDs**: Seven Longhorn CRDs have `preserveUnknownFields` drift that must be ignored to prevent perpetual sync loops (commits `7ae1870`, `fbf5e19`)
- **Prune disabled** (`prune: false`): Prevents accidental deletion of storage resources during sync
- **Additional finalizers**: `pre-delete-finalizer` ensures proper cleanup of Longhorn resources on Application deletion

## Consequences

- Dynamic persistent volume provisioning works out of the box for any workload
- Data is replicated 3x across nodes, surviving single-node failures
- Longhorn adds significant operational complexity — it runs multiple controllers, CSI sidecars, and a manager per node
- The `ignoreDifferences` workaround is fragile and may need updating when Longhorn CRDs change between versions
- Disabling prune means orphaned Longhorn resources must be cleaned up manually
- Storage performance is limited by the underlying node disks and network bandwidth
