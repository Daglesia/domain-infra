# One Postgresql vs Multiple instances

## Status

Ticket created [here](https://git.daglesia.com/Magdalena/domain-infra/issues/23).

## Context

Currently the resources to run the Kubernetes cluster are small, such as Raspberry Pi devices and low-power mini PC. Bundling each application with its own embedded PostgreSQL instance increases memory, CPU, storage, and operational overhead, and it leads to duplicated database administration effort.

On these small platforms, multiple separate database instances can quickly exhaust resources, reduce overall stability, and increase backup and restore complexity. A shared, centrally managed PostgreSQL service is more cost efficient and could be easier to maintain than many lightly used internal instances spread across charts.

## Decision

I will adopt one central PostgreSQL deployment for the cluster instead of allowing every application chart to include its own internal PostgreSQL instance. Applications that need relational storage will use a common, shared PostgreSQL service and connect to dedicated databases or schemas as appropriate.

This central database will be provisioned and managed independently of the application charts. Individual applications will no longer define their own standalone PostgreSQL dependencies in their Helm charts unless there is a strong, unavoidable justification.

This decision also extends to Redis/Valkey databases, but as currently there are only 2 of such databases it does not have as strong priority.

## Consequences

Positive:
- Lower combined memory and CPU usage.
- Stops errors related to bundling Postgres with charts (i.e. Penpot)
- Simpler application chart maintenance and fewer duplicate database configurations.

Negative:
- More coupling between applications and the shared PostgreSQL service.
- Shared database service becomes a more critical dependency and a single point of failure.
- Some applications may require migration from embedded instances to shared database schemas.