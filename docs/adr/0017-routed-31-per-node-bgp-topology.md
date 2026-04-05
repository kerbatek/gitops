# ADR-0017: Routed /31 Per-Node BGP Topology

## Status

Accepted

## Context

After adopting Cilium as the cluster networking stack in [ADR-0016](0016-cilium-replaces-flannel-metallb-kube-proxy.md), the original flat production node network remained a poor fit for the desired routing model.

The previous approach relied on:

- a shared L2 segment for all Kubernetes nodes
- a single router peer model
- one common local ASN across nodes
- direct node routing assumptions that only hold on a shared subnet

This was workable for the earlier Flannel and MetalLB setup, but it created problems once production moved to Cilium native routing and per-node BGP advertisement:

- node reachability and route installation depended on shared-subnet behavior instead of explicit routed links
- BGP topology was less deterministic than the testing cluster design
- production and testing were too close conceptually, increasing the risk of VLAN or ASN overlap
- scaling down or replacing individual nodes still carried shared-network coupling

Testing already validated a stricter routed design in which each node has a dedicated `/31` point-to-point link to the MikroTik L3 device, paired with its own VLAN and BGP session.

## Decision

We will run the main cluster node network as a routed per-node topology built from dedicated `/31` links.

For each surviving production node:

- the node gets its own VLAN
- the node gets its own `/31` point-to-point subnet to the MikroTik L3 device
- the MikroTik SVI IP is the node's default gateway
- the node runs its own eBGP session to the MikroTik device
- the node uses a unique local ASN

Production and testing identifiers must remain disjoint:

- testing VLANs and ASNs must not be reused in production
- production VLANs and ASNs must not be reused in testing

This design applies to all production nodes, including control planes and workers. The production cluster now targets three control planes and three workers, so the routed topology is defined for six nodes.

Cilium native routing in production will therefore assume explicit routed next hops instead of flat-L2 direct node reachability. Production Cilium configuration must keep `routingMode: native` and disable `autoDirectNodeRoutes`.

## Consequences

- Node-to-router topology is explicit and deterministic: one node, one VLAN, one `/31`, one BGP peer, one local ASN.
- Production now matches the routed model validated in testing, reducing architectural drift between environments.
- Route ownership is clearer: pod CIDRs and service VIPs are advertised from nodes over explicit eBGP sessions instead of depending on shared broadcast-domain behavior.
- Production and testing separation is stronger because VLAN and ASN ranges are intentionally non-overlapping.
- Replacing or removing workers is simpler because the network model is already per-node rather than tied to a shared node subnet.
- Router configuration is more verbose: every production node requires its own VLAN SVI and BGP neighbor.
- Cluster changes now require tighter coordination between infrastructure and GitOps, because node IPs, VLANs, gateways, and Cilium BGP resources must stay aligned.
- Operational debugging moves from "shared subnet issues" toward explicit per-node routing and peering checks, which is more rigorous but also less forgiving of mismatched values.
