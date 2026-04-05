# ADR-0018: Cilium-Managed API VIP with kubePrism for Node-Local API Access

## Status

Accepted

## Context

Under the earlier Talos VIP model, the Kubernetes API endpoint was owned directly by the control plane nodes. That approach becomes problematic once production moves to routed `/31` node links and Cilium-managed service advertisement:

- the external API endpoint should be advertised consistently through the same BGP control plane used for other LoadBalancer services
- node-local components must not depend on the external VIP being present during bootstrap or recovery
- Cilium itself must be able to reach the Kubernetes API before the externally advertised VIP is guaranteed to exist

Testing validated an alternative model:

- node-local components access the API through Talos kubePrism on `localhost:7445`
- the external Kubernetes API VIP is exposed as a Cilium `LoadBalancer` Service
- Cilium LB IPAM owns the API VIP allocation from a dedicated `/32` pool
- the API VIP is advertised over BGP like other service VIPs

This separates internal bootstrap and recovery behavior from the externally advertised API address.

## Decision

We will use kubePrism for node-local Kubernetes API access and a Cilium-managed LoadBalancer VIP for the external production API endpoint.

Specifically:

- node-local components such as Cilium agents and operator will use `k8sServiceHost: localhost` and `k8sServicePort: 7445`
- the external production API endpoint will be a dedicated Cilium `LoadBalancer` Service
- the API VIP will come from a dedicated `CiliumLoadBalancerIPPool` containing a single `/32`
- the API VIP will be advertised over the same routed BGP model as other service VIPs
- the external API VIP is a Cilium-managed service address, not a Talos-owned interface VIP

Talos machine configuration for control-plane nodes must therefore:

- treat the external API address as a certificate SAN and cluster endpoint
- avoid relying on a Talos-managed interface VIP for steady-state operation

## Consequences

- Cilium bootstrap is more reliable because node-local components talk to kubePrism and do not depend on the external VIP during startup.
- The external API endpoint behaves like other routed service VIPs and fits the BGP-based production networking model.
- Control-plane access is split cleanly into two paths: local bootstrap/recovery through kubePrism, external client access through the Cilium-managed VIP.
- API VIP allocation must be modeled carefully in GitOps: the dedicated pool and service selection must remain aligned so the intended `/32` is assigned.
- Talos and Cilium configuration must remain coordinated: the advertised VIP, Talos cluster endpoint, and API server certificate SANs all need to match.
- Recovery procedures are more specialized than with a simple Talos VIP, because the control plane can be up before the external VIP is advertised. This is an operational consequence and is documented in runbooks rather than in this ADR.
- Future production reboots and control-plane changes require validating both paths: kubePrism for node-local access and the Cilium VIP for external access.
