Status: needs-info

# Deploy the always-on monitoring service

Provision production hosting and PostgreSQL so collection continues while the Mac sleeps.
Add migrations, backups, restoration, uptime checks, error monitoring, deployment, and rollback.
Hosting choice or approval is required before implementation can finish.

## Release 0.2.0 evidence

Provider-neutral production configuration, PostgreSQL migrations, backup, checksum, restore, readiness, uptime, error-monitoring hook, deployment, and rollback paths are implemented and validated locally.
The scheduler rereads persisted Watchlists every cycle and runs fixed official feeds plus credential-gated YouTube, X, and Instagram official API collection without requiring the Mac app.
A fresh PostgreSQL database passed all 46 backend tests after migrations `003` through `005` rolled back and reapplied.
User-supplied official-source requests enforce HTTPS, public pinned DNS, redirect revalidation, and response-size bounds, while healthy zero-result provider responses remain connected live results.
A real backup restored into a fresh database with all five migrations.
The local service remained healthy for the 45-second observation window.

## External blocker

An authorized production host, PostgreSQL service, HTTPS domain, monitoring destination, and deployment credentials are required for a reachable deployment and real Mac sleep/wake proof.
