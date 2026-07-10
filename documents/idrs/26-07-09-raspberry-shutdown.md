# Raspberry Pi shutdown

## Status

Proposed.

## Context

8th to 9th of July the Raspberry Pi has been unaccessible for ~14 hours until personally resetted manually by plugging on and off. No logs have been registered of the event, but the device was very hot to the touch, and possibly overloaded with too much services to bear. The moment it stopped working was shortly after installation of victoria-metrics. Also the moment the app was added, the ArgoCD server crashed with logs suggesting lack of memory on the device. After this it was clear the device should have less apps on it, and move a little bit more to the other agent. For context, Forgejo and Postgresql were both hosted on the device, as well as Kubernetes, ingress-nginx and ArgoCD.

## Decision

The Forgejo and Postgresql will be offloaded to `dag-mini-pc`, leaving only Kubernetes orchestration, ingress-nginx and ArgoCD on the Raspberry Pi. Device-wise, cooling for the Raspberry Pi should also be provided as soon as possible.

This is a manual data migration, not a simple `values.yaml` change. Both Forgejo (`charts/forgejo`) and the shared PostgreSQL cluster (`charts/cnpg/postgresql`) currently use `local-path` storage with `nodeAffinity` hardcoded to `raspberka-ekran`. Moving them requires:
- Provisioning new local storage on `dag-mini-pc`
- Copying the Postgres data directory and Forgejo's git/LFS data across
- Updating `node_affinity_config` in both charts' `values.yaml` to point at `dag-mini-pc`
- A maintenance/downtime window while data is copied and services are cut over

This decision supersedes the node placement established in ADR `26-06-15-multiple-postgresql-instances`, which pinned the shared PostgreSQL cluster to `raspberka-ekran`.

On the Raspberry Pi there will be more logs set up, to not guess the next time something happens — specifically, persistent journald logging (to survive a hard power loss without an in-memory-only log buffer) plus victoria-metrics node-level metrics, so future incidents are diagnosable without needing physical access to the device.

victoria-metrics is already deployed on `dag-mini-pc`. For now it stays there; if it proves too heavy a load on `dag-mini-pc` as well, it will be removed or reconsidered.

## Consequences

Positive:
- Less likely for the incident to happen again
- I became aware of the limitations on the Raspberry Pi
- It became apparent more logging and health checking is required

Negative:
- More load to the `dag-mini-pc` instead
- Website was down for ~14 hours, and no backup service was provided during this time
- Migration itself introduces a further planned downtime window for Forgejo and Postgresql
