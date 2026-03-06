# ADR-0005: Ingress-Nginx as DaemonSet with Static LoadBalancer IP

## Status

Accepted

## Context

With MetalLB providing LoadBalancer support (see [ADR-0004](0004-metallb-with-ebgp-for-load-balancing.md)), we need an Ingress controller to route external HTTP/HTTPS traffic to services inside the cluster.

Key requirements:
- Handle all HTTP/HTTPS ingress traffic for the cluster
- Ensure high availability — traffic should be handled by every eligible node
- Use a stable, predictable external IP for DNS records

## Decision

We will use ingress-nginx (chart version 4.11.3) deployed as a **DaemonSet** with a static LoadBalancer IP.

Key configuration choices:
- **DaemonSet mode** (instead of Deployment): Runs one ingress controller pod per node, ensuring traffic is handled close to where it arrives and scaling automatically with the cluster
- **Static LoadBalancer IP** (`10.0.216.1`): Assigned via `loadBalancerIP`, providing a stable IP for external DNS A records
- **`externalTrafficPolicy: Local`**: Preserves client source IPs by avoiding extra SNAT hops, at the cost of potentially uneven load distribution
- **ServerSideApply** enabled to handle field ownership conflicts with the ingress-nginx CRDs

## Consequences

- Every worker node runs an ingress controller pod, providing node-level redundancy
- The static IP `10.0.216.1` can be used in DNS records without worrying about IP changes
- Client source IPs are preserved for logging and access control purposes
- DaemonSet mode uses more resources than a Deployment (one pod per node vs. fixed replica count)
- Adding new nodes automatically adds ingress capacity without manual scaling
