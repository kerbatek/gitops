# ADR-0004: MetalLB with eBGP for Bare-Metal Load Balancing

## Status

Accepted

## Context

Running Kubernetes on bare-metal means there is no cloud provider to provision LoadBalancer services. Without a solution, Services of type `LoadBalancer` remain in `Pending` state indefinitely.

We needed a bare-metal load balancer that can:
- Assign external IPs to LoadBalancer services
- Advertise those IPs to the network so they are routable
- Work with our existing network infrastructure that supports BGP

## Decision

We will use MetalLB (chart version 0.15.3) with eBGP peering to provide LoadBalancer functionality on bare metal.

Key configuration choices:
- **eBGP mode**: MetalLB peers with the network router via BGP to advertise service IPs, making them routable across the network
- **Speaker excluded from control-plane nodes**: The MetalLB speaker runs only on worker nodes (`node-role.kubernetes.io/control-plane` DoesNotExist), keeping control-plane nodes focused on cluster management
- **IP pool and BGP peer config**: Managed via plain YAML in `k8s/infra/metallb/config.yaml`, sourced as a second source alongside the Helm chart

## Consequences

- LoadBalancer services get real, routable external IPs via BGP advertisement
- The network router must be configured to accept BGP peering from MetalLB speakers
- Control-plane nodes don't participate in traffic forwarding, reducing their blast radius
- BGP configuration is tightly coupled to the physical network — changes to the router or AS numbers require updating MetalLB config
- MetalLB speaker pods must run on nodes with direct network connectivity to the BGP peer
