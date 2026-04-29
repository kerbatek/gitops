# Vaultwarden Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy Vaultwarden to the production cluster as a repo-managed Argo CD application with Longhorn-backed persistence, public TLS ingress on `vault.mrembiasz.pl`, and runtime secrets managed through Sealed Secrets.

**Architecture:** Add a new raw-manifest workload under `k8s/infra/vaultwarden/` and a matching child Argo CD `Application` under `k8s/argocd/apps/`. Keep the service single-replica with SQLite on a single PVC, expose it through `ingress-nginx`, and let the existing `secrets` application deliver the sealed runtime secret before the Vaultwarden app syncs.

**Tech Stack:** Kubernetes YAML, Argo CD, Kustomize, Sealed Secrets, Longhorn, ingress-nginx, cert-manager, kubeconform, kubectl

---

## File Structure

- Create: `k8s/infra/vaultwarden/kustomization.yaml`
- Create: `k8s/infra/vaultwarden/pvc.yaml`
- Create: `k8s/infra/vaultwarden/service.yaml`
- Create: `k8s/infra/vaultwarden/deployment.yaml`
- Create: `k8s/infra/vaultwarden/ingress.yaml`
- Create: `k8s/infra/secrets/vaultwarden/vaultwarden-env-sealed.yaml`
- Create: `k8s/argocd/apps/vaultwarden.yaml`
- Write only: `docs/superpowers/plans/2026-04-28-vaultwarden.md`

Responsibility split:

- `k8s/infra/vaultwarden/` owns the workload, service, storage, and ingress.
- `k8s/infra/secrets/vaultwarden/` owns the encrypted runtime configuration for Vaultwarden.
- `k8s/argocd/apps/vaultwarden.yaml` wires the workload into the production app-of-apps tree and sets sync ordering after the secrets app.

### Task 1: Create The Vaultwarden Workload Manifests

**Files:**
- Create: `k8s/infra/vaultwarden/kustomization.yaml`
- Create: `k8s/infra/vaultwarden/pvc.yaml`
- Create: `k8s/infra/vaultwarden/service.yaml`
- Create: `k8s/infra/vaultwarden/deployment.yaml`
- Create: `k8s/infra/vaultwarden/ingress.yaml`

- [ ] **Step 1: Verify the workload directory does not exist yet**

```bash
test -d k8s/infra/vaultwarden
```

Expected: exit code `1`

- [ ] **Step 2: Create the workload directory and write the Kustomize entrypoint, PVC, and Service**

```yaml
# k8s/infra/vaultwarden/kustomization.yaml
resources:
  - pvc.yaml
  - service.yaml
  - deployment.yaml
  - ingress.yaml
```

```yaml
# k8s/infra/vaultwarden/pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: vaultwarden-data
  namespace: vaultwarden
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
```

```yaml
# k8s/infra/vaultwarden/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: vaultwarden
  namespace: vaultwarden
spec:
  selector:
    app: vaultwarden
  ports:
    - name: http
      port: 80
      targetPort: http
```

- [ ] **Step 3: Run Kustomize and confirm it fails because the remaining resource files are still missing**

Run: `kubectl kustomize k8s/infra/vaultwarden`

Expected: FAIL with a missing-file error for `deployment.yaml` or `ingress.yaml`

- [ ] **Step 4: Write the Deployment and Ingress**

```yaml
# k8s/infra/vaultwarden/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vaultwarden
  namespace: vaultwarden
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: vaultwarden
  template:
    metadata:
      labels:
        app: vaultwarden
    spec:
      securityContext:
        fsGroup: 1000
      containers:
        - name: vaultwarden
          image: vaultwarden/server:1.33.2
          ports:
            - name: http
              containerPort: 80
          envFrom:
            - secretRef:
                name: vaultwarden-env
          resources:
            requests:
              cpu: 50m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
          readinessProbe:
            httpGet:
              path: /
              port: http
            initialDelaySeconds: 10
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /
              port: http
            initialDelaySeconds: 30
            periodSeconds: 30
          volumeMounts:
            - name: data
              mountPath: /data
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: vaultwarden-data
```

```yaml
# k8s/infra/vaultwarden/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: vaultwarden
  namespace: vaultwarden
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/proxy-body-size: "128m"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - vault.mrembiasz.pl
      secretName: vaultwarden-tls
  rules:
    - host: vault.mrembiasz.pl
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: vaultwarden
                port:
                  number: 80
```

- [ ] **Step 5: Build and validate the rendered workload manifests**

Run: `kubectl kustomize k8s/infra/vaultwarden | kubeconform -kubernetes-version 1.32.0 -schema-location default -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' -summary -verbose`

Expected: PASS with `Summary: 4 resources found parsing stdin - Valid: 4, Invalid: 0, Errors: 0, Skipped: 0`

- [ ] **Step 6: Commit the workload manifests**

```bash
git add k8s/infra/vaultwarden/kustomization.yaml \
  k8s/infra/vaultwarden/pvc.yaml \
  k8s/infra/vaultwarden/service.yaml \
  k8s/infra/vaultwarden/deployment.yaml \
  k8s/infra/vaultwarden/ingress.yaml
git commit -m "feat: add vaultwarden workload manifests"
```

### Task 2: Add The Vaultwarden Runtime Sealed Secret

**Files:**
- Create: `k8s/infra/secrets/vaultwarden/vaultwarden-env-sealed.yaml`

- [ ] **Step 1: Verify the sealed secret file is not present yet**

Run: `test -f k8s/infra/secrets/vaultwarden/vaultwarden-env-sealed.yaml`

Expected: exit code `1`

- [ ] **Step 2: Generate a strong admin token and create the sealed secret manifest**

```bash
mkdir -p k8s/infra/secrets/vaultwarden
export VAULTWARDEN_ADMIN_TOKEN="$(openssl rand -hex 32)"
kubectl create secret generic vaultwarden-env \
  -n vaultwarden \
  --from-literal=DOMAIN=https://vault.mrembiasz.pl \
  --from-literal=SIGNUPS_ALLOWED=false \
  --from-literal=WEBSOCKET_ENABLED=true \
  --from-literal=ROCKET_PORT=80 \
  --from-literal=ADMIN_TOKEN="$VAULTWARDEN_ADMIN_TOKEN" \
  --dry-run=client -o yaml | \
  kubeseal --format yaml > k8s/infra/secrets/vaultwarden/vaultwarden-env-sealed.yaml
unset VAULTWARDEN_ADMIN_TOKEN
```

Expected: file `k8s/infra/secrets/vaultwarden/vaultwarden-env-sealed.yaml` created with `kind: SealedSecret`

- [ ] **Step 3: Confirm the sealed secret targets the correct namespace and secret name**

Run: `sed -n '1,80p' k8s/infra/secrets/vaultwarden/vaultwarden-env-sealed.yaml`

Expected output includes:

```yaml
metadata:
  name: vaultwarden-env
  namespace: vaultwarden
```

- [ ] **Step 4: Validate the sealed secret manifest**

Run: `kubeconform -kubernetes-version 1.32.0 -schema-location default -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' -summary -verbose k8s/infra/secrets/vaultwarden/vaultwarden-env-sealed.yaml`

Expected: PASS with `Valid: 1, Invalid: 0, Errors: 0`

- [ ] **Step 5: Commit the sealed secret**

```bash
git add k8s/infra/secrets/vaultwarden/vaultwarden-env-sealed.yaml
git commit -m "feat: add vaultwarden runtime secret"
```

### Task 3: Register Vaultwarden In Argo CD

**Files:**
- Create: `k8s/argocd/apps/vaultwarden.yaml`

- [ ] **Step 1: Verify the child application file does not exist yet**

Run: `test -f k8s/argocd/apps/vaultwarden.yaml`

Expected: exit code `1`

- [ ] **Step 2: Create the child Argo CD Application**

```yaml
# k8s/argocd/apps/vaultwarden.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: vaultwarden
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "2"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/kerbatek/gitops.git
    targetRevision: main
    path: k8s/infra/vaultwarden
  destination:
    server: https://kubernetes.default.svc
    namespace: vaultwarden
  syncPolicy:
    automated:
      selfHeal: true
      prune: true
    syncOptions:
      - CreateNamespace=true
```

- [ ] **Step 3: Validate the Argo CD Application manifest**

Run: `kubeconform -kubernetes-version 1.32.0 -schema-location default -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' -summary -verbose k8s/argocd/apps/vaultwarden.yaml`

Expected: PASS with `Valid: 1, Invalid: 0, Errors: 0`

- [ ] **Step 4: Confirm the testing overlay remains unchanged**

Run: `kubectl kustomize k8s/overlays/testing/apps`

Expected: PASS and rendered output does not contain `name: vaultwarden`

- [ ] **Step 5: Commit the Argo CD wiring**

```bash
git add k8s/argocd/apps/vaultwarden.yaml
git commit -m "feat: add vaultwarden argocd application"
```

### Task 4: Run Full Repository Validation

**Files:**
- Modify: none
- Validate: `k8s/**/*.yaml`

- [ ] **Step 1: Rebuild the Vaultwarden workload and inspect the rendered output**

Run: `kubectl kustomize k8s/infra/vaultwarden`

Expected: PASS and output contains one `PersistentVolumeClaim`, one `Service`, one `Deployment`, and one `Ingress`

- [ ] **Step 2: Run the same kubeconform command used by CI across the repo**

Run:

```bash
find k8s -name '*.yaml' \
  ! -name 'kustomization.yaml' \
  ! -path '*/overlays/*/patches/*' \
  -print0 | xargs -0 kubeconform \
  -kubernetes-version 1.32.0 \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  -skip CiliumBGPClusterConfig,CiliumBGPPeerConfig,CiliumBGPAdvertisement,CiliumLoadBalancerIPPool \
  -summary \
  -verbose
```

Expected: PASS with no invalid manifests

- [ ] **Step 3: Review the Vaultwarden-only change history before sync**

Run: `git log --stat --oneline -- k8s/argocd/apps/vaultwarden.yaml k8s/infra/vaultwarden k8s/infra/secrets/vaultwarden`

Expected: output shows only Vaultwarden-related commits and file paths

- [ ] **Step 4: Commit any final manifest cleanup if validation required edits**

```bash
git add k8s/argocd/apps/vaultwarden.yaml \
  k8s/infra/vaultwarden \
  k8s/infra/secrets/vaultwarden/vaultwarden-env-sealed.yaml
git commit -m "chore: finalize vaultwarden manifests"
```

- [ ] **Step 5: Trigger Argo CD sync and verify runtime behavior after merge**

Run:

```bash
argocd app sync vaultwarden
argocd app wait vaultwarden --health --sync --timeout 300
kubectl -n vaultwarden get pods,pvc,ingress,secret
```

Expected:

```text
application 'vaultwarden' synced and healthy
deployment pod Running
vaultwarden-data PVC Bound
vaultwarden ingress present
vaultwarden-env secret present
```
