# Replacing ingress-nginx with Traefik

## Status

Accepted. Phase 1 (controller swap) is implemented. Phase 2 (Gateway API) is proposed and not started.

## Context

The cluster routed all external HTTP(S) traffic through the community `ingress-nginx` controller (chart 4.11.3, deployed from `apps/conf/ingress-nginx.yaml`). The Kubernetes project retired that controller in March 2026: it no longer receives updates or security patches. Leaving an internet-facing controller unpatched is not acceptable, and the Ingress API itself is feature-frozen in favour of Gateway API.

Constraints, carried over from ADR 26-06-15 and ADR 26-07-09:

- The hardware is small (Raspberry Pi and a low-power mini PC). The Pi has already failed from overload, so the replacement must be light.
- Popular, stable software is preferred over cutting-edge projects.
- Roughly a dozen workloads depend on `ingressClassName: nginx` and a handful of `nginx.ingress.kubernetes.io/*` annotations (`force-ssl-redirect`, `proxy-body-size`). Rewriting every chart at the same time as swapping the controller is a large blast radius for a single-operator cluster.
- cert-manager's HTTP-01 solver in the `letsencrypt-issuer` ClusterIssuer is bound to the `nginx` ingress class.

Options considered:

- **Traefik with its Ingress NGINX provider.** Reads existing Ingresses and translates nginx annotations at runtime. Also implements Gateway API, so a later move to Gateway API needs no second controller change. A single small deployment.
- **Envoy Gateway.** Gateway-API-native and well regarded, but heavier, with no annotation compatibility. Every Ingress would have to be rewritten up front.
- **F5 NGINX Ingress Controller / NGINX Gateway Fabric.** Different annotation prefix (`nginx.org/`) and different semantics from the community controller, so it is not a drop-in replacement either.
- **Go straight to Gateway API with any controller.** The right end state, but it couples the urgent security fix to a rewrite of every chart, including upstream charts that do not yet expose HTTPRoute values.

## Decision

Adopt **Traefik** as the cluster's ingress controller, in two phases.

### Why Traefik

- **It is the only option that avoids rewriting every chart now.** Its Ingress NGINX provider understands `ingressClassName: nginx` and the nginx annotations this cluster actually uses. The urgent problem is an unpatched controller, and this fixes it without touching any application chart, so a failed migration can be rolled back by restoring the old manifest.
- **It does not force a second migration later.** The same controller implements Gateway API, which is where the Kubernetes project is heading. Phase 2 is then a gradual, per-application change, with no further controller swap.
- **It fits the hardware.** It is one small deployment with a few tens of MiB of memory in practice, with no operator, no extra CRD-heavy control plane and no sidecars. That matters after the Raspberry Pi overload in ADR 26-07-09.
- **It meets the "popular and stable" preference.** Traefik is a long-established, widely deployed project. It is also what k3s ships by default, so it is a familiar component on this cluster's distribution, with plenty of documentation for it. Several platform vendors have also announced it as their ingress-nginx replacement, which suggests the migration path will stay well supported.
- **The alternatives each cost more here.** Envoy Gateway would force an immediate rewrite of every Ingress and is heavier. F5's NGINX controllers use different annotations and semantics, so they would need a rewrite as well. Going straight to Gateway API would tie the security fix to a rewrite of charts that don't expose HTTPRoute values yet.

The trade-off, recorded under Consequences, is that the NGINX provider covers the common annotations, not all of them, and that Traefik's Helm values have changed between chart versions.

**Phase 1: controller swap (done).**

- Deploy Traefik as a thin local chart, `charts/traefik`, wrapping the upstream `traefik` chart as a pinned dependency, with an `Application` at `apps/conf/traefik.yaml`. This follows the repo's usual pattern.
- Enable the Ingress NGINX provider (`providers.kubernetesIngressNGINX`, with `ingressClass: nginx` and `controllerClass: k8s.io/ingress-nginx`). Disable the plain Kubernetes Ingress provider so Ingresses are not served twice.
- Own the `nginx` `IngressClass` in `charts/traefik/templates/ingressclass.yaml`. The provider only discovers Ingresses through an IngressClass object, and the old class disappears with ingress-nginx.
- Leave every application chart and the cert-manager issuer unchanged. Ingresses keep `ingressClassName: nginx`.

**Phase 2: Gateway API (proposed).**

- Install the standard-channel Gateway API CRDs, enable Traefik's Gateway provider, and define one shared `Gateway` with an HTTPS listener per hostname.
- Enable Gateway API support in cert-manager. Switch the ClusterIssuer's HTTP-01 solver to `gatewayHTTPRoute` only after the last Ingress is gone.
- Migrate applications one at a time. `charts/flagship-website` already ships an HTTPRoute template and goes first. Wrapped upstream charts stay on Ingress until they, or a small local template, can provide an HTTPRoute.
- Annotations with no Gateway API equivalent become Traefik `Middleware` objects attached through filters (request body limits for Forgejo and Penpot, forward-auth for Authentik).
- When no Ingress remains, disable the NGINX provider and remove the IngressClass template.

## Consequences

Positive:

- The cluster is back on a maintained controller with no application chart changes.
- One component serves both Ingress and Gateway API, so phase 2 is incremental and does not require another controller swap.
- Traefik runs as a single small pod, with modest memory limits, which suits the hardware.
- The default request body limit of the NGINX provider (1 MiB) matches nginx's default, so behaviour is unchanged. Per-Ingress `proxy-body-size` annotations continue to apply.

Negative:

- The NGINX provider covers the common annotations, not all of them. Anything outside that set, such as the commented-out Authentik auth annotations on Jellyfin, must be re-tested if re-enabled.
- The provider's Helm key was renamed between chart versions (`kubernetesIngressNginx` before v40, `kubernetesIngressNGINX` from v40). A chart upgrade can break values validation, so Renovate PRs for this chart need a `helm template` check.
- Traefik now sits on ports 80/443 of the node k3s's servicelb binds to. Traefik is a single replica, so it is a single point of failure, the same as ingress-nginx was.
- The cutover caused a short outage: nothing listened on 80/443 between removing ingress-nginx and Traefik's servicelb pods starting, plus a further period of 404s until the `nginx` IngressClass was recreated.

## Migration notes

Things that went differently from the plan, for the next person doing something similar:

- **ingress-nginx was not managed by a live ArgoCD Application.** Its resources still carried an Argo tracking annotation, but the Application no longer existed (it was not in `kubectl get apps -n argocd`), so `argocd app delete --cascade` was not possible. The namespace and the cluster-scoped objects (IngressClass, `ingress-nginx-admission` webhook, ClusterRoles and bindings) were removed by hand.
- **The namespace stuck in `Terminating`** with no remaining content or finalizers reported, and was cleared through the namespace `finalize` endpoint.
- **k3s's servicelb DaemonSet survives deletion of its namespace.** `svclb-ingress-nginx-controller-*` lives in `kube-system` and kept ports 80/443 bound, leaving Traefik's `svclb-traefik-*` pods `Pending` until it was deleted by hand.
- **Without an IngressClass, Traefik ignores all Ingresses.** After ingress-nginx was removed every host returned 404 until the `nginx` IngressClass was applied.
- **Applications missing from ArgoCD.** `cert-manager`, `wikijs` and the `analytics` (VictoriaMetrics) app were not registered, and `docs.daglesia.com` and `analytics.daglesia.com` were already down before the migration, unrelated to it.

## Follow-ups

- Commit `charts/traefik/templates/ingressclass.yaml` and delete `apps/conf/ingress-nginx.yaml`.
- Verify with real use: a large Forgejo push or LFS upload, a Penpot upload and OIDC login, the n8n editor and Jellyfin playback (websockets), Authentik login.
- Force one certificate renewal to confirm HTTP-01 works through Traefik.
- Register `cert-manager`, `wikijs` and `analytics` as ArgoCD Applications (check `argocd app diff` first), and investigate why `docs` and `analytics` were down.
- Update `README.md`: replace the `ingress-nginx` example and add `apps/conf/traefik.yaml` to the bootstrap steps.
- Decide when to start phase 2, and write a follow-up ADR if the plan changes.