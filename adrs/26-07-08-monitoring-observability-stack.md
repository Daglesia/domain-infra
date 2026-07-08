# Cluster Monitoring / Health-Check Service

## Status

Proposed.

## Context

The cluster currently has no metrics, alerting, or health-check layer. All of it runs on modest hardware — the same class of hardware that motivated ADR 26-06-15 to consolidate onto a single shared PostgreSQL instance instead of one-per-app. Any monitoring stack has to respect that constraint: it needs to observe roughly a dozen small workloads (Forgejo, Authentik, Penpot, Jellyfin, Wiki.js, the shared Postgres cluster, cert-manager, ingress-nginx) without itself becoming the heaviest thing running on the cluster.

The default, most-discussed option for Kubernetes is the `kube-prometheus-stack` Helm chart (Prometheus + Alertmanager + Grafana + `node-exporter` + `kube-state-metrics`). It is the de-facto standard and extremely well documented, but Prometheus's single-node TSDB is comparatively RAM-hungry — commonly cited around 4 GiB+ memory once Grafana and the operator are added, which is a large bite out of a Pi or a small mini-PC. On resource-constrained hardware this can crowd out the actual workloads the cluster exists to run.

The broader 2026 landscape includes several alternatives:

- **VictoriaMetrics** (`victoria-metrics-k8s-stack`) — a Prometheus-protocol-compatible metrics stack (PromQL-superset "MetricsQL") that swaps Prometheus's TSDB for a more compressed, single-binary storage engine. Widely reported to use 5-10x less RAM and a fraction of the disk of Prometheus for equivalent data, while still using the familiar `node-exporter` / `kube-state-metrics` / Grafana components underneath.
- **Mimir**, **Cortex**, **Thanos** — all solve horizontal scale and multi-tenant, long-retention storage for large fleets (hundreds of nodes, millions of active series). None of that applies here; they add operational complexity (extra microservices, object storage, sharding) with no corresponding benefit at this scale.
- **OpenObserve / SigNoz / GreptimeDB** — unified logs+metrics+traces platforms built on newer storage engines (ClickHouse, custom object stores). Interesting and lower-friction operationally, but newer projects with thinner track records and smaller communities than Prometheus-family tooling — a worse fit given the stated preference for popular, stable software over cutting-edge.
- **Netdata / Beszel / Uptime Kuma** — genuinely minimal, purpose-built for simple host/service health dashboards. Good complements, but not a substitute for label-based, queryable cluster metrics (pod restarts, PVC pressure, Postgres connection counts, HPA behavior) that the rest of this repo's charts already expose hooks for (e.g. `web-hpa.yaml`'s CPU/memory targets, the CNPG `monitoring.enablePodMonitor` flags).

## Decision

Adopt **VictoriaMetrics** as the cluster's metrics and alerting backend, deployed via the `victoria-metrics-k8s-stack` Helm chart, following the same pattern as every other chart in this repo (thin local chart wrapping an upstream dependency, `values.yaml` for cluster-specific config, an `Application` manifest under `apps/`).

Concretely:
- `VMSingle` (not `VMCluster`) for storage — single-instance is the right trade-off here for the same reason the shared Postgres cluster runs `instances: 1` (ADR 26-06-15): this is a single small cluster, not a multi-tenant fleet, so HA storage would add cost without a corresponding benefit.
- Keep `node-exporter` and `kube-state-metrics` (bundled as chart dependencies) for host- and object-level metrics — this preserves compatibility with the standard Kubernetes/Grafana dashboard ecosystem rather than locking into a proprietary agent.
- Grafana (also bundled) as the single dashboarding UI, exposed the same way other internal tools are (nginx `Ingress` + `letsencrypt-issuer`, optionally behind the existing Authentik outpost the way Jellyfin is).
- `VMAlert` + Alertmanager for basic alerting (pod crash-looping, PVC near-full, Postgres down) — low-value without it, and it's included in the same chart at no extra operational cost.
- CNPG's `monitoring.enablePodMonitor` (currently `false` in `charts/cnpg/postgresql/values.yaml` and `charts/cnpg/operator/values.yaml`) can be turned on once this stack exists, since the VictoriaMetrics operator understands `PodMonitor`/`ServiceMonitor`-shaped CRDs the same way Prometheus-operator does.

Logs (Loki/VictoriaLogs) and traces are explicitly out of scope for this decision — metrics and alerting cover the immediate "is something broken" need. Log aggregation can be a follow-up ADR if/when it's actually needed.

## Consequences

Positive:
- Materially lower baseline memory/CPU footprint than `kube-prometheus-stack`, which matters directly on `dag-mini-pc` and `raspberka-ekran`.
- No new query language or dashboard format to learn — MetricsQL is a PromQL superset, and the huge library of community Grafana dashboards built for `kube-prometheus-stack` mostly work unmodified.
- Built on the same widely-adopted, actively-maintained project (VictoriaMetrics has years of production use and a large user base) rather than a newer, less-proven all-in-one platform.
- Fits the repo's existing conventions: one more thin chart + `Application` manifest, secrets (Grafana admin password, Alertmanager webhook URLs if any) go through the same `secrets.yaml` + SOPS + `age` pattern as everything else.

Negative:
- MetricsQL's extensions are a (small, well-documented) departure from pure PromQL — a mild lock-in if a future migration back to plain Prometheus were ever desired.
- One more component competing for the mini-PC/Pi's limited resources, even if it's the lightest available option; resource requests/limits will need to be set conservatively (similar to the deliberately-minimal `cloudnative-pg` values in `charts/cnpg/operator/values.yaml`).
- Single-instance `VMSingle` means monitoring itself is not highly available — acceptable here since the workloads being monitored aren't HA either, but worth stating explicitly so it isn't assumed away later.
