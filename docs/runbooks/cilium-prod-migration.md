# Cilium Production Migration Runbook

Migrates production (`url-shortener`) from Flannel + MetalLB + kube-proxy to Cilium.

**Tested on**: testing cluster (2026-03-23)
**Cilium version**: 1.17.1
**Cluster**: 3 CP + 5 workers, Talos v1.12.2

> All `kubectl` and `kubectl apply -f` commands assume the working directory is the **gitops repo root**.
> Terraform commands assume the working directory is `infra/environments/production`.

---

## Reference Values

| | Production |
|---|---|
| Cluster VIP | `10.0.217.5:6443` |
| MikroTik BGP peers | `10.0.217.0`, `10.0.217.2`, `10.0.217.6`, `10.0.217.8`, `10.0.217.10`, `10.0.217.12` |
| Local ASNs | `65201–65206` |
| Peer ASN | `64513` |
| LB IP pool | `10.1.128.0/26` |
| Pod CIDR | `10.245.0.0/16` |
| CP nodes | `10.0.217.1`, `10.0.217.3`, `10.0.217.7` |
| Worker nodes | `10.0.217.9`, `10.0.217.11`, `10.0.217.13` |

---

## Part 1: Pre-Migration Preparation

### 1.1 GitOps — verify main branch

The `testing` branch must be merged to `main` before migration. Verify these files are present on `main`:

- `k8s/argocd/apps/cilium.yaml` — with prod values (`k8sServiceHost: localhost`, `k8sServicePort: 7445`, `ipv4NativeRoutingCIDR: 10.245.0.0/16`)
- `k8s/infra/cilium/config.yaml` — BGP resources with prod values (ASN 64512, peer `10.0.215.1`, pool `10.1.128.0/26`)
- `k8s/infra/cilium/coredns-configmap.yaml` — CoreDNS fix (critical)

**Do not delete `k8s/argocd/apps/metallb.yaml` from main yet** — that happens in Part 4 after Cilium is verified.

### 1.2 Terraform — enable Cilium for production

**File**: `environments/production/main.tf`

These values are already set (added as part of migration prep):
```hcl
enable_cilium = true
pod_cidr      = "10.245.0.0/16"
```

`enable_cilium = true` sets `cluster.network.cni.name: none` and `cluster.proxy.disabled: true`.
`pod_cidr` sets `cluster.network.podSubnets` so kube-controller-manager allocates from `10.245.0.0/16`.

> Production uses `10.245.0.0/16` — **different from testing's `10.244.0.0/16`** — because both clusters
> advertise per-node pod CIDRs to the same MikroTik router. Overlapping CIDRs would create routing conflicts.

### 1.3 MikroTik preparation

Production now uses a routed `/31` design with **no overlap** with testing:
- Testing VLANs: `2161–2166`
- Production VLANs: `2171–2176`
- Testing ASNs: `65101–65106`
- Production ASNs: `65201–65206`

Create six VLAN SVIs and six eBGP neighbors on MikroTik before the migration.

> Replace `<TRUNK_IF>` with the interface or bridge that carries the production VLAN trunk on your router.
> Do **not** create any SVI for VIP `10.0.217.5/32` — Cilium advertises that as a BGP `/32`.

```routeros
# RouterOS v7

/interface vlan
add name=prod-cp-1 interface=<TRUNK_IF> vlan-id=2171
add name=prod-cp-2 interface=<TRUNK_IF> vlan-id=2172
add name=prod-cp-3 interface=<TRUNK_IF> vlan-id=2173
add name=prod-worker-1 interface=<TRUNK_IF> vlan-id=2174
add name=prod-worker-2 interface=<TRUNK_IF> vlan-id=2175
add name=prod-worker-3 interface=<TRUNK_IF> vlan-id=2176

/ip address
add address=10.0.217.0/31 interface=prod-cp-1
add address=10.0.217.2/31 interface=prod-cp-2
add address=10.0.217.6/31 interface=prod-cp-3
add address=10.0.217.8/31 interface=prod-worker-1
add address=10.0.217.10/31 interface=prod-worker-2
add address=10.0.217.12/31 interface=prod-worker-3

/routing/bgp/instance
add name=prod-k8s as=64513

/routing/bgp/connection
add name=prod-cp-1 instance=prod-k8s local.role=ebgp \
    local.address=10.0.217.0 remote.address=10.0.217.1 remote.as=65201
add name=prod-cp-2 instance=prod-k8s local.role=ebgp \
    local.address=10.0.217.2 remote.address=10.0.217.3 remote.as=65202
add name=prod-cp-3 instance=prod-k8s local.role=ebgp \
    local.address=10.0.217.6 remote.address=10.0.217.7 remote.as=65203
add name=prod-worker-1 instance=prod-k8s local.role=ebgp \
    local.address=10.0.217.8 remote.address=10.0.217.9 remote.as=65204
add name=prod-worker-2 instance=prod-k8s local.role=ebgp \
    local.address=10.0.217.10 remote.address=10.0.217.11 remote.as=65205
add name=prod-worker-3 instance=prod-k8s local.role=ebgp \
    local.address=10.0.217.12 remote.address=10.0.217.13 remote.as=65206
```

Quick verification on MikroTik before touching the cluster:

```routeros
/interface vlan print where name~"prod-"
/ip address print where interface~"prod-"
/routing/bgp/connection print where name~"prod-"
```

Existing MetalLB BGP sessions can be left in place before the cutover. They will stop advertising once MetalLB is removed. Pod CIDR routes (`10.245.x.0/24`) and the API VIP (`10.0.217.5/32`) will appear after Cilium BGP comes up.

### 1.4 Verify current cluster health

```bash
talosctl --context url-shortener health
kubectl --context admin@url-shortener get nodes
kubectl --context admin@url-shortener -n argocd get apps
```

---

## Part 2: Migration — Day Of

> Cilium must be installed via **Helm CLI first**, then handed to ArgoCD.
> Removing Flannel kills pod networking including ArgoCD — it cannot install itself.

### Step 1 — Disable auto-sync on ArgoCD applications

Prevents ArgoCD from fighting changes during the migration window.
The app-of-apps must also be paused — otherwise it will recreate the `metallb` Application
within ~3 minutes of Step 2 (it still sees `metallb.yaml` on `main`).

```bash
# Pause app-of-apps first to stop it recreating metallb
kubectl --context admin@url-shortener -n argocd patch app app-of-apps \
  -p '{"spec":{"syncPolicy":{"automated":null}}}' --type=merge

kubectl --context admin@url-shortener -n argocd patch app metallb \
  -p '{"spec":{"syncPolicy":{"automated":null}}}' --type=merge

kubectl --context admin@url-shortener -n argocd patch app ingress-nginx \
  -p '{"spec":{"syncPolicy":{"automated":null}}}' --type=merge
```

### Step 2 — Delete MetalLB from ArgoCD (non-cascading)

Removes ArgoCD management without deleting live MetalLB resources.
MetalLB continues running and serving LB IPs during this step.

```bash
kubectl --context admin@url-shortener -n argocd delete app metallb
```

### Step 3 — Apply Terraform config (targeted, skip health check)

Pushes new Talos machine config to all nodes. The `talos_cluster_health` check is skipped
because the cluster will be briefly unhealthy when Flannel is removed.

```bash
# From infra/environments/production
terraform apply \
  -target='module.cluster.talos_machine_configuration_apply.controlplane' \
  -target='module.cluster.talos_machine_configuration_apply.worker'
```

Immediately after Terraform completes, **while nodes are rebooting**, delete all node objects.
This forces fresh pod CIDR allocation from `10.245.0.0/16` when nodes re-register:

```bash
kubectl --context admin@url-shortener delete nodes --all
```

> Deleting node objects during reboot is safe: CP nodes re-register as soon as kube-apiserver comes
> back up (static pod, persists across reboots). Workers re-register once Talos finishes booting.
> **Do NOT delete nodes before Terraform** — they would immediately re-register with the old CIDR.

Wait for the API server to become reachable, then verify all nodes returned with the new CIDR:

```bash
until kubectl --context admin@url-shortener get nodes &>/dev/null; do
  echo "Waiting for API server..."; sleep 10
done

kubectl --context admin@url-shortener get nodes -o \
  jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.podCIDR}{"\n"}{end}'
# All CIDRs should be from 10.245.x.x
```

### Step 4 — Apply CoreDNS fix immediately

**Critical** — Talos's link-local DNS proxy (`169.254.116.108`) is only reachable via Flannel
routing. Without this fix, all external DNS resolution fails once nodes reboot without Flannel,
and ArgoCD loses connectivity to GitHub.

Apply this as soon as the API server is reachable — do **not** wait for `rollout status` here,
since CoreDNS pods cannot reach running state until Cilium is installed in Step 6.

```bash
# From gitops repo root
kubectl --context admin@url-shortener apply -f k8s/infra/cilium/coredns-configmap.yaml
kubectl --context admin@url-shortener -n kube-system rollout restart deployment coredns
```

### Step 5 — Delete MetalLB resources

With Flannel gone, MetalLB is no longer functioning. Clean up its namespace:

```bash
kubectl --context admin@url-shortener delete namespace metallb-system --ignore-not-found
```

If the namespace gets stuck in `Terminating` (MetalLB webhook finalizer with unreachable backend),
force it:

```bash
kubectl --context admin@url-shortener get namespace metallb-system -o json \
  | python3 -c "import sys,json; d=json.load(sys.stdin); d['spec']['finalizers']=[]; print(json.dumps(d))" \
  | kubectl --context admin@url-shortener replace --raw \
      /api/v1/namespaces/metallb-system/finalize -f -
```

> **Note**: LoadBalancer IPs are lost at this point. ingress-nginx will show `<pending>` until
> Cilium assigns a new IP from `10.1.128.0/26`.

### Step 6 — Install Cilium via Helm CLI

```bash
helm repo add cilium https://helm.cilium.io/ && helm repo update

helm install cilium cilium/cilium --version 1.17.1 \
  --namespace kube-system \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=localhost \
  --set k8sServicePort=7445 \
  --set ipam.mode=kubernetes \
  --set bgpControlPlane.enabled=true \
  --set bpf.masquerade=true \
  --set routingMode=native \
  --set autoDirectNodeRoutes=true \
  --set ipv4NativeRoutingCIDR=10.245.0.0/16 \
  --set loadBalancer.mode=dsr \
  --set loadBalancer.algorithm=maglev \
  --set operator.replicas=1 \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=false \
  --set cgroup.autoMount.enabled=false \
  --set cgroup.hostRoot=/sys/fs/cgroup \
  --set "securityContext.capabilities.ciliumAgent={CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
  --set "securityContext.capabilities.cleanCiliumState={NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}"
```

> `routingMode=native` is mandatory on Talos — DSR is incompatible with VXLAN tunneling.
> `cgroup` and `securityContext` values are required by Talos's hardened security model.
> `k8sServiceHost=localhost` + `k8sServicePort=7445` uses Talos kubePrism for strict HA API access from node-local components (no dependency on a single CP IP or on a Cilium-managed VIP during bootstrap).

### Step 7 — Wait for Cilium to be healthy

All 8 agents must be ready. CoreDNS `rollout status` (deferred from Step 4) can also be
confirmed here now that a CNI is present:

```bash
kubectl --context admin@url-shortener -n kube-system rollout status daemonset cilium
kubectl --context admin@url-shortener -n kube-system rollout status deployment coredns

CILIUM_POD=$(kubectl --context admin@url-shortener get pod -n kube-system \
  -l k8s-app=cilium -o name | head -1)
kubectl --context admin@url-shortener exec -n kube-system $CILIUM_POD -- cilium status --brief
```

Expected: `OK`. If it shows "Stale status data", wait 2–5 minutes — BPF programs are
compiled per-node for the first time (CPU-intensive but one-time).

Verify DNS now works end-to-end:

```bash
kubectl --context admin@url-shortener run dns-test --rm -it --image=busybox --restart=Never \
  -- nslookup google.com
```

### Step 8 — Restart all pods to get Cilium networking

Pods that started under Flannel have stale network interfaces. Restart everything:

```bash
for ns in $(kubectl --context admin@url-shortener get ns -o jsonpath='{.items[*].metadata.name}'); do
  kubectl --context admin@url-shortener -n $ns rollout restart deployment 2>/dev/null || true
  kubectl --context admin@url-shortener -n $ns rollout restart daemonset 2>/dev/null || true
  kubectl --context admin@url-shortener -n $ns rollout restart statefulset 2>/dev/null || true
done

# CoreDNS: second restart to ensure it runs under Cilium networking (first restart in Step 4
# may have landed on a node still mid-boot)
kubectl --context admin@url-shortener -n kube-system rollout restart deployment coredns
kubectl --context admin@url-shortener -n kube-system rollout status deployment coredns
```

### Step 9 — Apply BGP resources

```bash
# From gitops repo root
kubectl --context admin@url-shortener apply -f k8s/infra/cilium/config.yaml
kubectl --context admin@url-shortener apply -f k8s/infra/cilium/coredns-configmap.yaml
```

Wait for BGP sessions to establish (~30 seconds):

```bash
CILIUM_POD=$(kubectl --context admin@url-shortener get pod -n kube-system \
  -l k8s-app=cilium -o name | head -1)
kubectl --context admin@url-shortener exec -n kube-system $CILIUM_POD -- cilium bgp peers
```

Expected: all peers show `Established`.

### Step 10 — Verify LB IP assignment and routing

```bash
kubectl --context admin@url-shortener get svc -n ingress-nginx

CILIUM_POD=$(kubectl --context admin@url-shortener get pod -n kube-system \
  -l k8s-app=cilium -o name | head -1)
kubectl --context admin@url-shortener exec -n kube-system $CILIUM_POD -- \
  cilium bgp routes advertised ipv4 unicast
```

Expected: LB IP (`10.1.128.x/32`) + per-node pod CIDRs (`10.245.x.0/24` × 8 nodes) advertised.

Verify MikroTik routing table shows the new routes (check router directly).

---

## Part 3: Known Issues and Fixes

These issues occurred during the testing migration and may appear on production.

### ArgoCD repo-server CrashLoopBackOff after DNS failure

If CoreDNS wasn't patched fast enough, ArgoCD repo-server may be stuck in CrashLoopBackOff:

```bash
kubectl --context admin@url-shortener -n argocd rollout restart deployment argocd-repo-server
```

### ArgoCD application-controller "operation not permitted" on ClusterIP

Stale socket state from pre-Cilium networking. Delete the pod to force recreation:

```bash
kubectl --context admin@url-shortener -n argocd delete pod \
  -l app.kubernetes.io/name=argocd-application-controller
```

### Longhorn CSI chain broken after restart

If Longhorn volumes aren't mounting, `longhorn-driver-deployer` init container may be stuck
waiting on stale DNS:

```bash
kubectl --context admin@url-shortener -n longhorn-system rollout restart daemonset longhorn-manager
# Wait 60s, then delete the stuck deployer pod if it exists
kubectl --context admin@url-shortener -n longhorn-system delete pod -l app=longhorn-driver-deployer
```

### Controller-manager / scheduler crash-looping at startup

kube-scheduler and kube-controller-manager may crash-loop on first boot while waiting for the
Cilium agent on their node to be ready. **Self-resolves** once all Cilium agents are healthy.
Expected wait: 5–10 minutes.

If it persists beyond 15 minutes with API server under heavy load, check the etcd leader:

```bash
talosctl --context url-shortener \
  -n 10.0.215.10,10.0.215.11,10.0.215.12 etcd status
```

If one CP node is disproportionately loaded, move the leader off it:

```bash
talosctl --context url-shortener -n <overloaded-cp-ip> etcd forfeit-leadership
```

### cilium-operator high restart count (40+ is normal)

The operator restarts many times while establishing leader election during initial stabilization.
Self-resolves within 15–20 minutes. Monitor:

```bash
kubectl --context admin@url-shortener -n kube-system get pod \
  -l name=cilium-operator -w
```

---

## Part 4: ArgoCD Handoff

Once BGP is established, LB IPs are assigned, and external connectivity is verified:

### Step 4.1 — Remove MetalLB from main and push

```bash
git checkout main
git rm k8s/argocd/apps/metallb.yaml
git commit -m "feat: replace MetalLB with Cilium on production"
git push origin main
```

### Step 4.2 — Disable auto-sync on the cilium app before Helm handoff

The `cilium` ArgoCD Application has `selfHeal: true`. Once ArgoCD recovers, it will begin
reconciling the Cilium resources installed by Helm. Disable auto-sync briefly to prevent
interference while the Helm secret is being removed:

```bash
kubectl --context admin@url-shortener -n argocd patch app cilium \
  -p '{"spec":{"syncPolicy":{"automated":null}}}' --type=merge
```

### Step 4.3 — Delete Helm release secret (hands off to ArgoCD)

ArgoCD cannot manage a Helm release it didn't install. Deleting the release secrets causes
ArgoCD to adopt the existing resources on next sync without reinstalling.

> Note: this also removes the ability to `helm rollback`. If you need a Helm-level rollback
> path, preserve the latest revision secret before running this command.

```bash
kubectl --context admin@url-shortener -n kube-system delete secret \
  -l owner=helm,name=cilium
```

### Step 4.4 — Re-enable auto-sync and sync all apps

```bash
# Re-enable cilium auto-sync
kubectl --context admin@url-shortener -n argocd patch app cilium \
  -p '{"spec":{"syncPolicy":{"automated":{"selfHeal":true,"prune":true}}}}' --type=merge

# Re-enable app-of-apps (which will now see metallb.yaml removed from main)
kubectl --context admin@url-shortener -n argocd patch app app-of-apps \
  -p '{"spec":{"syncPolicy":{"automated":{"selfHeal":true,"prune":true}}}}' --type=merge

# Re-enable ingress-nginx
kubectl --context admin@url-shortener -n argocd patch app ingress-nginx \
  -p '{"spec":{"syncPolicy":{"automated":{"selfHeal":true,"prune":true}}}}' --type=merge
```

Force sync the cilium app if it does not auto-sync within 3 minutes:

```bash
kubectl --context admin@url-shortener -n argocd get app cilium
# If argocd CLI available:
argocd app sync cilium
# Otherwise trigger via kubectl:
kubectl --context admin@url-shortener -n argocd patch app cilium \
  -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}' \
  --type=merge
```

Expected result: `Synced / Healthy`.

### Step 4.5 — Full Terraform apply

Validates that `talos_cluster_health` passes and syncs Terraform state cleanly:

```bash
# From infra/environments/production
terraform apply
```

---

## Part 5: Verification Checklist

```bash
CILIUM_POD=$(kubectl --context admin@url-shortener get pod -n kube-system \
  -l k8s-app=cilium -o name | head -1)

# All Cilium agents healthy, KubeProxyReplacement active
kubectl --context admin@url-shortener exec -n kube-system $CILIUM_POD -- cilium status

# BGP sessions established
kubectl --context admin@url-shortener exec -n kube-system $CILIUM_POD -- cilium bgp peers

# Routes advertised: LB IPs + pod CIDRs
kubectl --context admin@url-shortener exec -n kube-system $CILIUM_POD -- \
  cilium bgp routes advertised ipv4 unicast

# LoadBalancer services have IPs
kubectl --context admin@url-shortener get svc -A | grep LoadBalancer

# ArgoCD apps all Synced/Healthy
kubectl --context admin@url-shortener -n argocd get apps

# External connectivity
curl -I https://mrembiasz.pl
```

Verify on MikroTik:
- LB IP route (`10.1.128.x/32`) present in routing table
- Per-node pod CIDR routes (`10.245.x.0/24` × 8 nodes) present

---

## Part 6: Rollback

If migration must be aborted before ArgoCD handoff:

```bash
# Remove Cilium
helm --kube-context admin@url-shortener uninstall cilium -n kube-system

# Revert Terraform:
# In environments/production/main.tf, set:
#   enable_cilium = false
#   pod_cidr      = "10.244.0.0/16"   # restore original Flannel CIDR
# Then apply:
terraform apply \
  -target='module.cluster.talos_machine_configuration_apply.controlplane' \
  -target='module.cluster.talos_machine_configuration_apply.worker'
# Talos re-enables Flannel + kube-proxy on next reboot

# Restore GitOps on main — git revert the commit that removed metallb.yaml
# Re-enable app-of-apps auto-sync
kubectl --context admin@url-shortener -n argocd patch app app-of-apps \
  -p '{"spec":{"syncPolicy":{"automated":{"selfHeal":true,"prune":true}}}}' --type=merge
# ArgoCD will re-create MetalLB on next sync

# Sync Terraform state
terraform apply
```

---

## Appendix: Talos-Specific Cilium Requirements

These Helm values are **required on Talos** and absent from upstream Cilium docs:

| Value | Why |
|---|---|
| `routingMode: native` | DSR is incompatible with VXLAN; Talos uses direct L3 routing |
| `autoDirectNodeRoutes: true` | Required for native routing when nodes are on the same L2 segment |
| `ipv4NativeRoutingCIDR: 10.245.0.0/16` | Tells Cilium to route pod traffic natively (not masquerade) within this CIDR |
| `cgroup.autoMount.enabled: false` | Talos mounts cgroupv2 itself; Cilium must not attempt to remount |
| `cgroup.hostRoot: /sys/fs/cgroup` | Explicit path required since auto-mount is disabled |
| `securityContext.capabilities.*` | Talos drops Linux capabilities by default; must be explicitly granted |

CoreDNS **must** forward to explicit upstream IPs (`1.1.1.1 8.8.8.8`) instead of `/etc/resolv.conf`.
Talos's link-local DNS proxy (`169.254.116.108`) is only reachable through Flannel's routing table —
it becomes unreachable the moment Flannel is disabled. See `k8s/infra/cilium/coredns-configmap.yaml`.
