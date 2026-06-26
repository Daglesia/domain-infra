GitOps source of truth for my own self-hosted Kubernetes cluster, deployed and reconciled by ArgoCD.

## How it works

- **`apps/`** — one ArgoCD `Application` manifest per workload. Most point at a local chart (`path: charts/<name>`, `targetRevision: HEAD`); a few (e.g. `ingress-nginx`) reference an upstream chart directly.
- **`charts/`** — thin local Helm charts, one per app. Each wraps a single upstream chart as a `dependencies:` entry in its `Chart.yaml`, pinned to a specific version, with cluster-specific config in `values.yaml`.
- **`secrets.yaml`** files alongside `values.yaml` hold credentials, encrypted with [SOPS](https://github.com/getsops/sops) using an `age` key (see `.sops.yaml`). ArgoCD decrypts them in-cluster via [argocd-helm-secrets](https://github.com/JuniorJPDJ/argocd-helm-secrets).
- **`adrs/`** — architecture decision records for non-obvious infra calls.

## Setting up from scratch

1. **Bootstrap ArgoCD itself**, including the SOPS-aware `repo-server` image — see `charts/argocd/Chart.yaml` (a Rancher `HelmChart` resource if using k3s, otherwise install `argo-cd` via the equivalent values).

2. **Generate an age key and give it to ArgoCD**, so it can decrypt `secrets.yaml` files:
   ```bash
   age-keygen -o age.key
   kubectl -n argocd create secret generic sops-age --from-file=age.key
   ```
   Mount it into `argocd-repo-server` (volume + `SOPS_AGE_KEY_FILE` env var — already wired up if you used the `argocd` chart above).

3. **Add the public half of that key to `.sops.yaml`** so future secrets are encrypted for it.

4. **Apply the Application manifests:**
   ```bash
   kubectl apply -f apps/ -R
   ```
   ArgoCD takes over from here — each `Application` syncs its chart automatically.

## Adding a new app

1. Create `charts/<name>/` with a `Chart.yaml` (upstream chart as a dependency) and `values.yaml`.
2. Encrypt any secrets into `charts/<name>/secrets.yaml` with `sops -e`.
3. Add an `Application` manifest under `apps/`.
4. Commit — ArgoCD does the rest.
