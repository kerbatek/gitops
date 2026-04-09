# Portfolio Chart Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move portfolio Helm chart ownership from `gitops` to `portfolio`, keep environment-specific Argo CD overrides in `gitops`, and replace Argo CD Image Updater with an app-repo-owned release flow.

**Architecture:** Keep the Argo CD `portfolio` Application in `gitops`, but point it at a Helm chart stored in `portfolio`. Use a simple single-source Argo Application with inline environment overrides because the current override surface is small. Let `portfolio` CI build immutable GHCR images and commit the release tag back into its own chart so the app repo owns code, image version, and deployment shape together.

**Tech Stack:** Helm v3, Argo CD Applications, Kustomize overlays, GitHub Actions, GHCR, Kubernetes

---

## Assumptions

- `gitops` remote: `https://github.com/kerbatek/gitops.git`
- `portfolio` remote: `https://github.com/kerbatek/portfolio.git`
- Target chart path in `portfolio`: `deploy/helm/portfolio`
- Production and testing both consume the chart from `portfolio` `main` by default
- If testing needs to validate an unreleased app branch later, override `spec.source.targetRevision` in `k8s/overlays/testing/apps/patches/portfolio.yaml` for that branch only; do not introduce a permanent `testing` branch in `portfolio`
- Initial release tag in the migrated chart should match the current deployed SHA from `charts/portfolio/.argocd-source-portfolio.yaml`, which is `sha-7a285fa` at plan-writing time

## File Map

**`portfolio` repo**

- Create: `../portfolio/deploy/helm/portfolio/Chart.yaml`
- Create: `../portfolio/deploy/helm/portfolio/values.yaml`
- Create: `../portfolio/deploy/helm/portfolio/templates/_helpers.tpl`
- Create: `../portfolio/deploy/helm/portfolio/templates/deployment.yaml`
- Create: `../portfolio/deploy/helm/portfolio/templates/service.yaml`
- Create: `../portfolio/deploy/helm/portfolio/templates/ingress.yaml`
- Modify: `../portfolio/.github/workflows/ci.yml`
- Modify: `../portfolio/README.md`

**`gitops` repo**

- Modify: `k8s/argocd/apps/portfolio.yaml`
- Modify: `k8s/overlays/testing/apps/patches/portfolio.yaml`
- Modify: `README.md`
- Delete later: `charts/portfolio/Chart.yaml`
- Delete later: `charts/portfolio/values.yaml`
- Delete later: `charts/portfolio/templates/_helpers.tpl`
- Delete later: `charts/portfolio/templates/deployment.yaml`
- Delete later: `charts/portfolio/templates/service.yaml`
- Delete later: `charts/portfolio/templates/ingress.yaml`
- Delete later: `charts/portfolio/.argocd-source-portfolio.yaml`
- Delete later: `k8s/argocd/apps/argocd-image-updater.yaml`
- Delete later: `k8s/infra/argocd-image-updater/portfolio.yaml`

## Delivery Sequence

1. Merge a `portfolio` PR that adds the chart and CI-owned release tagging.
2. Wait for the first successful `main` workflow run that pushes images and commits the chart tag in `portfolio`.
3. Merge a `gitops` PR that switches the Argo CD Application to the chart in `portfolio`.
4. Verify the cluster is healthy and Argo reports the app sourced from `portfolio`.
5. Merge a cleanup `gitops` PR that removes the old local chart and Argo CD Image Updater resources.

### Task 1: Copy the Existing Chart into `portfolio`

**Files:**
- Create: `../portfolio/deploy/helm/portfolio/Chart.yaml`
- Create: `../portfolio/deploy/helm/portfolio/values.yaml`
- Create: `../portfolio/deploy/helm/portfolio/templates/_helpers.tpl`
- Create: `../portfolio/deploy/helm/portfolio/templates/deployment.yaml`
- Create: `../portfolio/deploy/helm/portfolio/templates/service.yaml`
- Create: `../portfolio/deploy/helm/portfolio/templates/ingress.yaml`
- Test: `../portfolio/deploy/helm/portfolio/*` via `helm template`

- [ ] **Step 1: Copy the current chart into the app repo**

Run:

```bash
cd /Users/kerbatek/development/portfolio
mkdir -p deploy/helm
cp -R /Users/kerbatek/development/gitops/charts/portfolio deploy/helm/portfolio
find deploy/helm/portfolio -maxdepth 2 -type f | sort
```

Expected: `deploy/helm/portfolio/Chart.yaml`, `values.yaml`, and the `templates/` files all exist.

- [ ] **Step 2: Verify the copied chart still renders before refactoring**

Run:

```bash
cd /Users/kerbatek/development/portfolio
helm template portfolio deploy/helm/portfolio > /tmp/portfolio-chart-before-refactor.yaml
rg 'portfolio-(frontend|backend)' /tmp/portfolio-chart-before-refactor.yaml
```

Expected: the render succeeds and the output contains both `portfolio-frontend` and `portfolio-backend` resources.

- [ ] **Step 3: Commit the raw chart import**

```bash
cd /Users/kerbatek/development/portfolio
git add deploy/helm/portfolio
git commit -m "feat: add portfolio helm chart to app repo"
```

### Task 2: Refactor the Chart for Repo-Owned Releases and Generic Defaults

**Files:**
- Modify: `../portfolio/deploy/helm/portfolio/Chart.yaml`
- Modify: `../portfolio/deploy/helm/portfolio/values.yaml`
- Modify: `../portfolio/deploy/helm/portfolio/templates/_helpers.tpl`
- Modify: `../portfolio/deploy/helm/portfolio/templates/ingress.yaml`
- Test: `../portfolio/deploy/helm/portfolio/*` via `helm template`

- [ ] **Step 1: Introduce a single release tag and neutral ingress defaults**

Update `../portfolio/deploy/helm/portfolio/Chart.yaml` to keep a stable chart version and set the app version to the current live SHA:

```yaml
apiVersion: v2
name: portfolio
description: Personal portfolio page
type: application
version: 0.1.0
appVersion: sha-7a285fa
```

Update `../portfolio/deploy/helm/portfolio/values.yaml` so the chart has one repo-owned release tag and no environment-specific hostname baked in:

```yaml
global:
  imageTag: sha-7a285fa

frontend:
  image:
    repository: ghcr.io/kerbatek/portfolio-frontend
    pullPolicy: Always
  replicas: 2
  containerPort: 80
  resources:
    requests:
      cpu: 25m
      memory: 48Mi
    limits:
      cpu: 100m
      memory: 96Mi

backend:
  image:
    repository: ghcr.io/kerbatek/portfolio-backend
    pullPolicy: Always
  replicas: 2
  containerPort: 8080
  resources:
    requests:
      cpu: 25m
      memory: 64Mi
    limits:
      cpu: 100m
      memory: 128Mi

ingress:
  host: example.invalid
  ingressClassName: nginx
  tls: {}
```

- [ ] **Step 2: Make the Deployment template default to `global.imageTag`**

Update the image line inside `../portfolio/deploy/helm/portfolio/templates/_helpers.tpl`:

```gotemplate
{{- define "portfolio.deployment" -}}
{{- $imageTag := .values.image.tag | default .root.Values.global.imageTag -}}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .root.Release.Name }}-{{ .component }}
  labels:
    app: {{ .root.Release.Name }}-{{ .component }}
spec:
  replicas: {{ .values.replicas }}
  selector:
    matchLabels:
      app: {{ .root.Release.Name }}-{{ .component }}
  template:
    metadata:
      labels:
        app: {{ .root.Release.Name }}-{{ .component }}
    spec:
      containers:
        - name: {{ .component }}
          image: "{{ .values.image.repository }}:{{ $imageTag }}"
          imagePullPolicy: {{ .values.image.pullPolicy }}
          ports:
            - containerPort: {{ .values.containerPort }}
          readinessProbe:
            httpGet:
              path: {{ .probePath }}
              port: {{ .values.containerPort }}
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: {{ .probePath }}
              port: {{ .values.containerPort }}
            initialDelaySeconds: 10
            periodSeconds: 30
          resources:
            requests:
              cpu: {{ .values.resources.requests.cpu }}
              memory: {{ .values.resources.requests.memory }}
            limits:
              cpu: {{ .values.resources.limits.cpu }}
              memory: {{ .values.resources.limits.memory }}
{{- end }}
```

- [ ] **Step 3: Make TLS optional so environment config can stay in `gitops`**

Replace `../portfolio/deploy/helm/portfolio/templates/ingress.yaml` with:

```gotemplate
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ .Release.Name }}
  {{- with .Values.ingress.tls.clusterIssuer }}
  annotations:
    cert-manager.io/cluster-issuer: {{ . }}
  {{- end }}
spec:
  ingressClassName: {{ .Values.ingress.ingressClassName }}
  {{- with .Values.ingress.tls.secretName }}
  tls:
    - hosts:
        - {{ $.Values.ingress.host }}
      secretName: {{ . }}
  {{- end }}
  rules:
    - host: {{ .Values.ingress.host }}
      http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: {{ .Release.Name }}-backend
                port:
                  number: {{ .Values.backend.containerPort }}
          - path: /
            pathType: Prefix
            backend:
              service:
                name: {{ .Release.Name }}-frontend
                port:
                  number: {{ .Values.frontend.containerPort }}
```

- [ ] **Step 4: Render the chart with and without TLS**

Run:

```bash
cd /Users/kerbatek/development/portfolio
helm template portfolio deploy/helm/portfolio --set ingress.host=mrembiasz.pl > /tmp/portfolio-no-tls.yaml
helm template portfolio deploy/helm/portfolio \
  --set ingress.host=mrembiasz.pl \
  --set ingress.tls.secretName=portfolio-tls \
  --set ingress.tls.clusterIssuer=letsencrypt-prod > /tmp/portfolio-with-tls.yaml
rg 'cert-manager.io/cluster-issuer|secretName: portfolio-tls' /tmp/portfolio-with-tls.yaml
! rg 'cert-manager.io/cluster-issuer|secretName: portfolio-tls' /tmp/portfolio-no-tls.yaml
```

Expected: the TLS render contains the annotation and secret name; the non-TLS render contains neither.

- [ ] **Step 5: Commit the chart refactor**

```bash
cd /Users/kerbatek/development/portfolio
git add deploy/helm/portfolio/Chart.yaml \
  deploy/helm/portfolio/values.yaml \
  deploy/helm/portfolio/templates/_helpers.tpl \
  deploy/helm/portfolio/templates/ingress.yaml
git commit -m "refactor: make portfolio chart app-owned and environment-neutral"
```

### Task 3: Make `portfolio` CI Publish Images and Update Its Own Chart

**Files:**
- Modify: `../portfolio/.github/workflows/ci.yml`
- Modify: `../portfolio/README.md`
- Test: workflow logic via local diff review and a real `main` run after merge

- [ ] **Step 1: Update the workflow so image build stays separate from chart tagging**

Replace `../portfolio/.github/workflows/ci.yml` with:

```yaml
name: Build and Push to GHCR

on:
  push:
    branches: [main]

env:
  REGISTRY: ghcr.io

jobs:
  build-and-push:
    if: github.actor != 'github-actions[bot]'
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    strategy:
      matrix:
        include:
          - component: frontend
            context: ./frontend
            image: ghcr.io/${{ github.repository }}-frontend
          - component: backend
            context: ./backend
            image: ghcr.io/${{ github.repository }}-backend

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Log in to GHCR
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ matrix.image }}
          tags: |
            type=raw,value=latest
            type=sha,prefix=sha-

      - name: Build and push
        uses: docker/build-push-action@v6
        with:
          context: ${{ matrix.context }}
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}

  update-chart:
    if: github.actor != 'github-actions[bot]'
    needs: build-and-push
    runs-on: ubuntu-latest
    permissions:
      contents: write

    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          ref: main

      - name: Update chart release tag
        run: |
          SHORT_SHA="sha-${GITHUB_SHA::7}"
          sed -i.bak "s/^appVersion: .*/appVersion: ${SHORT_SHA}/" deploy/helm/portfolio/Chart.yaml
          sed -i.bak "s/^  imageTag: .*/  imageTag: ${SHORT_SHA}/" deploy/helm/portfolio/values.yaml
          rm deploy/helm/portfolio/Chart.yaml.bak deploy/helm/portfolio/values.yaml.bak

      - name: Commit chart release
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git add deploy/helm/portfolio/Chart.yaml deploy/helm/portfolio/values.yaml
          git diff --cached --quiet && exit 0
          git commit -m "chore: bump portfolio release to sha-${GITHUB_SHA::7} [skip ci]"
          git push
```

- [ ] **Step 2: Update the repo README so deployment ownership is accurate**

Replace the deployment section in `../portfolio/README.md` with:

```markdown
# Portfolio

Personal site built with React + Go, containerized and deployed via Argo CD.

**[mrembiasz.pl](https://mrembiasz.pl)**

## Stack

- React SPA (Vite) — frontend
- Go + Gin — content API backend
- Nginx Alpine — serves the frontend bundle
- Helm chart in `deploy/helm/portfolio`
- GitHub Actions → GHCR → Argo CD

See `docs/adr/` for architectural decisions.
```

- [ ] **Step 3: Verify the workflow file is syntactically clean and commit**

Run:

```bash
cd /Users/kerbatek/development/portfolio
git diff --check -- .github/workflows/ci.yml README.md deploy/helm/portfolio
git add .github/workflows/ci.yml README.md deploy/helm/portfolio
git commit -m "feat: let portfolio ci own chart release tags"
```

Expected: `git diff --check` exits `0`.

- [ ] **Step 4: Merge the `portfolio` PR and wait for the first release commit**

After merge to `main`, verify the workflow produced a follow-up bot commit:

```bash
cd /Users/kerbatek/development/portfolio
git fetch origin
git log --oneline origin/main -n 5
```

Expected: one of the latest commits matches `chore: bump portfolio release to sha-<7 chars>`.

### Task 4: Switch Argo CD to the Chart in `portfolio`

**Files:**
- Modify: `k8s/argocd/apps/portfolio.yaml`
- Modify: `k8s/overlays/testing/apps/patches/portfolio.yaml`
- Test: rendered overlay and live Application source fields

- [ ] **Step 1: Point the production Application at the chart in `portfolio`**

Replace `k8s/argocd/apps/portfolio.yaml` with:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: portfolio
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/kerbatek/portfolio.git
    targetRevision: main
    path: deploy/helm/portfolio
    helm:
      valuesObject:
        frontend:
          replicas: 3
        backend:
          replicas: 3
        ingress:
          host: mrembiasz.pl
          tls:
            secretName: portfolio-tls
            clusterIssuer: letsencrypt-prod
  destination:
    server: https://kubernetes.default.svc
    namespace: portfolio
  syncPolicy:
    automated:
      selfHeal: true
      prune: true
    syncOptions:
      - CreateNamespace=true
```

- [ ] **Step 2: Stop assuming `portfolio/testing` exists**

Replace `k8s/overlays/testing/apps/patches/portfolio.yaml` with:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: portfolio
  namespace: argocd
spec:
  source:
    helm:
      valuesObject:
        ingress:
          host: testing.mrembiasz.pl
          tls: {}
```

- [ ] **Step 3: Verify the testing overlay still builds**

Run:

```bash
cd /Users/kerbatek/development/gitops
kubectl kustomize k8s/overlays/testing/apps > /tmp/testing-apps.yaml
rg 'repoURL: https://github.com/kerbatek/portfolio.git|path: deploy/helm/portfolio|host: testing.mrembiasz.pl' /tmp/testing-apps.yaml
```

Expected: the rendered overlay contains the new `portfolio` repo URL, the chart path, and the testing host override.

- [ ] **Step 4: Commit the cutover without deleting the old chart yet**

```bash
cd /Users/kerbatek/development/gitops
git add k8s/argocd/apps/portfolio.yaml k8s/overlays/testing/apps/patches/portfolio.yaml
git commit -m "feat: source portfolio app from portfolio repo"
```

### Task 5: Verify the Live Cutover Before Cleanup

**Files:**
- Test only: live Argo CD Application and workload objects

- [ ] **Step 1: Confirm Argo CD now tracks the `portfolio` repo**

Run:

```bash
cd /Users/kerbatek/development/gitops
kubectl -n argocd get application portfolio -o yaml > /tmp/argocd-portfolio-app.yaml
rg 'repoURL: https://github.com/kerbatek/portfolio.git|path: deploy/helm/portfolio|targetRevision: main' /tmp/argocd-portfolio-app.yaml
```

Expected: all three fields are present in the live Application spec.

- [ ] **Step 2: Confirm the portfolio workload stayed healthy**

Run:

```bash
cd /Users/kerbatek/development/gitops
kubectl -n portfolio get deploy,svc,ingress
kubectl -n portfolio rollout status deployment/portfolio-frontend --timeout=120s
kubectl -n portfolio rollout status deployment/portfolio-backend --timeout=120s
```

Expected: both Deployments report `successfully rolled out`, and the Service/Ingress names are unchanged.

- [ ] **Step 3: Only proceed to cleanup if the app stayed healthy for at least one sync cycle**

Run:

```bash
cd /Users/kerbatek/development/gitops
kubectl -n argocd get application portfolio
```

Expected: `SYNC STATUS` is `Synced` and `HEALTH STATUS` is `Healthy`.

### Task 6: Remove the Old GitOps-Owned Chart and Image Updater

**Files:**
- Delete: `charts/portfolio/Chart.yaml`
- Delete: `charts/portfolio/values.yaml`
- Delete: `charts/portfolio/templates/_helpers.tpl`
- Delete: `charts/portfolio/templates/deployment.yaml`
- Delete: `charts/portfolio/templates/service.yaml`
- Delete: `charts/portfolio/templates/ingress.yaml`
- Delete: `charts/portfolio/.argocd-source-portfolio.yaml`
- Delete: `k8s/argocd/apps/argocd-image-updater.yaml`
- Delete: `k8s/infra/argocd-image-updater/portfolio.yaml`
- Modify: `README.md`

- [ ] **Step 1: Remove the old local chart and Image Updater resources**

Run:

```bash
cd /Users/kerbatek/development/gitops
git rm -r charts/portfolio
git rm k8s/argocd/apps/argocd-image-updater.yaml
git rm k8s/infra/argocd-image-updater/portfolio.yaml
```

Expected: the index shows the old chart and updater manifests staged for deletion.

- [ ] **Step 2: Update the GitOps README so it no longer claims portfolio chart ownership**

Edit `README.md` so these statements change:

```markdown
charts/
  # no local portfolio chart lives here anymore
```

```markdown
- `portfolio`: Helm chart sourced from the portfolio repository
```

```markdown
The portfolio workload is deployed from the Helm chart stored in the portfolio repository.
```

Remove the `argocd-image-updater` component and the note that portfolio tags are updated via `k8s/infra/argocd-image-updater/portfolio.yaml`.

- [ ] **Step 3: Verify the cleanup diff and commit**

Run:

```bash
cd /Users/kerbatek/development/gitops
git diff --check -- README.md
git add README.md
git commit -m "chore: remove gitops-owned portfolio chart and image updater"
```

Expected: `git diff --check` exits `0`.

### Task 7: Rollback Plan

**Files:**
- Revert candidate: `k8s/argocd/apps/portfolio.yaml`
- Revert candidate: `k8s/overlays/testing/apps/patches/portfolio.yaml`

- [ ] **Step 1: If the cutover fails before cleanup, revert only the Argo source switch**

Run:

```bash
cd /Users/kerbatek/development/gitops
git revert <commit-that-switched-portfolio-source>
```

Expected: Argo CD returns to the local chart in `gitops`, and no deleted files need to be restored because cleanup has not happened yet.

- [ ] **Step 2: If cleanup already happened, revert the cleanup commit first, then the cutover commit if necessary**

Run:

```bash
cd /Users/kerbatek/development/gitops
git revert <cleanup-commit>
git revert <cutover-commit>
```

Expected: the local chart, updater manifests, and old source wiring are restored in the correct order.

## Self-Review

- Spec coverage: the plan covers chart ownership, CI-owned release tagging, Argo source cutover, testing overlay behavior, cleanup, verification, and rollback.
- Placeholder scan: no `TBD`, `TODO`, or “handle later” language remains.
- Type consistency: the target chart path is consistently `deploy/helm/portfolio`, and the target repo is consistently `https://github.com/kerbatek/portfolio.git`.

Plan complete and saved to `docs/superpowers/plans/2026-04-09-portfolio-chart-migration.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
