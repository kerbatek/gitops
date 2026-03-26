# ADR-0016: Cilium Replaces Flannel, MetalLB, and kube-proxy

## Status

Accepted (supersedes [ADR-0004](0004-metallb-with-ebgp-for-load-balancing.md))

## Context

The cluster runs on Talos Linux with three separate networking components:

- **Flannel** (built-in Talos CNI) for pod-to-pod networking
- **kube-proxy** (iptables-based) for Service routing
- **MetalLB** (ArgoCD-managed) for LoadBalancer IP assignment and eBGP advertisement

This stack works but has limitations:

- Three independent components to configure, monitor, and debug
- No pod CIDR advertisement — pods are only reachable via Service IPs or node ports, requiring NAT for external-to-pod traffic
- iptables-based kube-proxy does not scale efficiently and adds latency compared to eBPF alternatives
- MetalLB speakers must run on every worker node, consuming resources even when not actively forwarding traffic

Cilium can replace all three with a unified eBPF-based networking stack that also adds per-node pod CIDR advertisement via BGP, making pods directly routable from the L3 switch without NAT.

## Decision

We will replace Flannel, kube-proxy, and MetalLB with **Cilium v1.17.1** as the unified CNI, service proxy, and load balancer.

### Talos Configuration

Talos machine config patches disable the built-in components when `enable_cilium = true`:

- `cluster.network.cni.name: none` — Talos skips Flannel installation
- `cluster.proxy.disabled: true` — Talos skips kube-proxy installation

### Cilium Configuration

Key settings:

- **`kubeProxyReplacement: true`** — Cilium handles all Service routing via eBPF, replacing kube-proxy
- **`ipam.mode: kubernetes`** — Uses Kubernetes-native pod CIDR allocations (compatible with Talos defaults)
- **`bgpControlPlane.enabled: true`** — Enables Cilium's BGP Control Plane (v2 API) for route advertisement
- **`bpf.masquerade: true`** — eBPF-based masquerading for pod-to-external traffic
- **`loadBalancer.mode: dsr`** — Direct Server Return for LoadBalancer services, avoiding return-path NAT
- **`loadBalancer.algorithm: maglev`** — Consistent hashing for connection affinity

### BGP Configuration (v2 API)

Cilium BGP v2 resources replace MetalLB's `IPAddressPool`, `BGPPeer`, and `BGPAdvertisement`:

| Cilium CRD | Replaces | Purpose |
|-------------|----------|---------|
| `CiliumLoadBalancerIPPool` | MetalLB `IPAddressPool` | Defines the IP range for LoadBalancer services |
| `CiliumBGPClusterConfig` | MetalLB `BGPPeer` | Defines local ASN and peer topology |
| `CiliumBGPPeerConfig` | (new) | Separates peer timers, graceful restart, and address families |
| `CiliumBGPAdvertisement` (lb-services) | MetalLB `BGPAdvertisement` | Advertises LoadBalancer IPs |
| `CiliumBGPAdvertisement` (pod-cidrs) | (new) | Advertises per-node pod CIDRs for direct pod routing |

### Deployment Pattern

Cilium is deployed as a multi-source ArgoCD Application (same pattern as MetalLB):

- Source 1: Helm chart from `https://helm.cilium.io/`
- Source 2: BGP resources from `k8s/infra/cilium/`

Testing overrides via kustomize patches adjust IP pools, ASN, peer addresses, and the Kubernetes API VIP.

### Rollout Strategy

Testing cluster first, production later. Cilium is bootstrapped via Helm CLI during the initial migration (since removing Flannel kills pod networking, including ArgoCD), then handed off to ArgoCD by deleting the Helm release secret and syncing the ArgoCD app.

## Consequences

- **Unified stack**: One component (Cilium) replaces three (Flannel + kube-proxy + MetalLB), reducing operational complexity
- **Direct pod routing**: Per-node pod CIDR advertisement via BGP makes pods directly routable from the network without NAT
- **eBPF performance**: Service routing via eBPF is more efficient than iptables, especially at scale
- **DSR for LoadBalancer**: Direct Server Return avoids return-path NAT, reducing latency for external traffic
- **Hubble observability**: Cilium includes Hubble for network flow visibility (relay enabled, UI disabled to save resources)
- **Migration risk**: Replacing the CNI requires a brief networking outage during the switchover — nodes must reboot to apply Talos config changes
- **MikroTik dependency**: The router must be configured to accept both LoadBalancer IP and pod CIDR routes via BGP
- **Cilium-specific CRDs**: BGP configuration now uses Cilium-specific CRDs rather than the more generic MetalLB CRDs
- **CoreDNS upstream DNS**: Removing Flannel breaks CoreDNS's default `forward . /etc/resolv.conf` path because Talos's link-local DNS proxy (`169.254.116.108`) is no longer reachable. The CoreDNS ConfigMap must be overridden to forward directly to `1.1.1.1` / `8.8.8.8`. This is managed via `k8s/infra/cilium/coredns-configmap.yaml` and must be applied immediately after Cilium installation during migration
- **Talos-specific Helm values**: Cilium on Talos requires `cgroup.autoMount.enabled=false`, `cgroup.hostRoot=/sys/fs/cgroup`, explicit `securityContext.capabilities`, and `routingMode=native` (DSR is incompatible with VXLAN tunneling)
- **MetalLB on production**: Production retains MetalLB until the production migration is completed
