# Testing Cluster: /31 Routed L3 BGP Design

**Date:** 2026-03-26
**Status:** Approved
**Repos affected:** `gitops` (Cilium), `infra` (Terraform)

---

## Goal

Replace the testing cluster's flat L2 topology (single VLAN 216, shared /24) with a fully routed L3 topology where each node has a dedicated /31 point-to-point link to the MikroTik L3 switch. Each node runs eBGP with a unique ASN, advertising pod CIDRs and LoadBalancer IPs. The API VIP is maintained via a Cilium LoadBalancer Service.

---

## Architecture

```
                        MikroTik L3 Switch (ASN 64513)
                        ┌──────────────────────────────────────────┐
  VLAN 2161 /31 ───────►│ SVI 10.0.216.0   BGP ◄── testing-cp-1 (ASN 65101)
  VLAN 2162 /31 ───────►│ SVI 10.0.216.2   BGP ◄── testing-cp-2 (ASN 65102)
  VLAN 2163 /31 ───────►│ SVI 10.0.216.6   BGP ◄── testing-cp-3 (ASN 65103)
  VLAN 2164 /31 ───────►│ SVI 10.0.216.8   BGP ◄── testing-worker-1 (ASN 65104)
  VLAN 2165 /31 ───────►│ SVI 10.0.216.10  BGP ◄── testing-worker-2 (ASN 65105)
  VLAN 2166 /31 ───────►│ SVI 10.0.216.12  BGP ◄── testing-worker-3 (ASN 65106)
                        │                                          │
                        │  BGP-learned routes:                     │
                        │  10.0.216.5/32   ← Cilium LB (apiserver) │
                        │  10.244.x.0/24   ← Cilium pod CIDRs     │
                        │  10.1.129.x/32   ← Cilium LB IPs        │
                        └──────────────────────────────────────────┘
```

**BGP sessions per node:** 1 — Cilium handles everything (pod CIDRs, LB IPs including the API VIP).

---

## IP & VLAN Plan

| Node | Hostname | VLAN | Node IP | Switch SVI | ASN |
|------|----------|------|---------|------------|-----|
| CP1 | testing-cp-1 | 2161 | 10.0.216.1/31 | 10.0.216.0 | 65101 |
| CP2 | testing-cp-2 | 2162 | 10.0.216.3/31 | 10.0.216.2 | 65102 |
| CP3 | testing-cp-3 | 2163 | 10.0.216.7/31 | 10.0.216.6 | 65103 |
| W1  | testing-worker-1 | 2164 | 10.0.216.9/31 | 10.0.216.8 | 65104 |
| W2  | testing-worker-2 | 2165 | 10.0.216.11/31 | 10.0.216.10 | 65105 |
| W3  | testing-worker-3 | 2166 | 10.0.216.13/31 | 10.0.216.12 | 65106 |

**VIP:** `10.0.216.5/32` — intentional gap (no SVI), purely a BGP /32 advertised by Cilium as a LoadBalancer IP.

**MikroTik ASN:** `64513`

---

## Why Unique ASN Per Node

With all nodes sharing a single ASN, the MikroTik cannot re-advertise pod CIDRs between nodes — BGP loop prevention drops routes that contain the receiving node's own ASN in the path. Each node must have a unique ASN so pod CIDR routes from node1 can be learned by node2 via the switch.

---

## Changes: Infra Repo (`../infra`)

### `modules/talos-cluster/variables.tf`

- Replace `vlan_id: number` with `node_vlans: list(number)` (per-node VLAN IDs)
- Replace `gateway: string` with `node_gateways: list(string)` (per-node switch SVIs)
- Keep `vip` variable but add `enable_bgp_vip: bool` to switch between ARP VIP and BGP VIP modes

### `modules/talos-cluster/vms.tf`

- `vlan_id = var.node_vlans[count.index]` (CP and worker VMs)
- `gateway = var.node_gateways[count.index]` (CP and worker VMs)
- IP mask: `/24` → `/31`

### `modules/talos-cluster/talos.tf`

- When `enable_bgp_vip = false`: Talos ARP VIP config patch on eth0 (existing behavior)
- When `enable_bgp_vip = true`: only add VIP to API Server cert SANs (no Talos VIP management)

### `environments/testing/main.tf`

```hcl
cluster_endpoint  = "https://10.0.216.5:6443"   # unchanged

node_vlans        = [2161, 2162, 2163, 2164, 2165, 2166]
node_gateways     = ["10.0.216.0", "10.0.216.2", "10.0.216.6",
                     "10.0.216.8", "10.0.216.10", "10.0.216.12"]
control_plane_ips = ["10.0.216.1", "10.0.216.3", "10.0.216.7"]
worker_ips        = ["10.0.216.9", "10.0.216.11", "10.0.216.13"]
vip               = "10.0.216.5"
enable_bgp_vip    = true
```

---

## Changes: GitOps Repo (`./`)

### `k8s/overlays/testing/apps/patches/cilium.yaml`

- Set `autoDirectNodeRoutes: false` (nodes are no longer on a shared L2 segment)
- Set `k8sServiceHost: localhost` and `k8sServicePort: 7445` to use Talos kubePrism for strict HA API access from node-local Cilium components

### `k8s/overlays/testing/infra/cilium/kustomization.yaml`

- Remove the single `peerAddress` patch
- Add `$patch: delete` on the base `bgp-cluster-config` (replaced by per-node configs)
- Add `bgp-node-configs.yaml` to resources

### New: `k8s/overlays/testing/infra/cilium/bgp-node-configs.yaml`

Six `CiliumBGPClusterConfig` objects, one per node. Each has:
- `nodeSelector` targeting `kubernetes.io/hostname: <hostname>`
- `localASN` unique per node (65101–65106)
- `peerAddress` set to that node's switch SVI
- `peerASN: 64513`
- `peerConfigRef: mikrotik-peer-config`

### New: `k8s/overlays/testing/infra/cilium/apiserver-vip.yaml`

Replaces kube-vip with a pure Cilium approach:
- `CiliumLoadBalancerIPPool` for `10.0.216.5/32`
- LoadBalancer `Service` targeting `component: kube-apiserver` static pods
- Cilium advertises the VIP via its existing BGP sessions — no extra DaemonSet needed

---

## Bootstrap Consideration

During initial cluster bring-up, Cilium must be installed before the VIP becomes available (it's a Cilium LoadBalancer Service). For the first bootstrap:

1. Apply Talos config — point `talosconfig` at a single CP node IP directly
2. Bootstrap cluster
3. ArgoCD deploys Cilium (including the apiserver-vip Service and IP pool) via GitOps
4. Once Cilium establishes BGP sessions, VIP `10.0.216.5` is advertised as a LoadBalancer IP
5. Subsequent access uses the VIP

### Recovery Hardening (2026-03-29)

After etcd disaster recovery testing, Cilium startup proved sensitive to `k8sServiceHost` pointing at the Cilium-managed VIP itself.  
To avoid control-plane bootstrap loops without introducing a single-node dependency, testing overlay now uses Talos kubePrism (`k8sServiceHost: localhost`, `k8sServicePort: 7445`) for Cilium's API access, while keeping the external client endpoint on VIP `10.0.216.5`.
Also ensure `CiliumLoadBalancerIPPool` (`apiserver-vip-pool`) exists before creating/recreating the `apiserver-vip` Service, so IPAM allocates `10.0.216.5` instead of taking an address from `main-pool`.

---

## Out of Scope

- MikroTik configuration (managed in `infra` repo or manually — VLAN trunk, SVIs, BGP neighbors)
- Proxmox bridge VLAN-aware configuration (managed in `infra` repo)
- Production cluster (changes are testing-only)
