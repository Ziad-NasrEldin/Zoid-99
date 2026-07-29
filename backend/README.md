# Zoid 99 backend

This service is the deployment-ready data and API foundation for the single-user macOS application.
It stores normalized research records, source health, opportunities, watchlists, notifications, and encrypted connector configuration.
The macOS ingestion worker collects credential-free official feeds on the configured refresh schedule and submits normalized research batches here.

## Requirements

- Node.js 22 or newer
- PostgreSQL 17
- Docker Compose is optional for the deterministic local database

## Local setup

1. Copy `.env.example` to `.env`.
2. Replace `ZOID99_API_TOKEN` with a random value containing at least 32 characters.
3. Replace `SECRETS_ENCRYPTION_KEY` with exactly 32 random bytes encoded as base64.
4. Start PostgreSQL with `docker compose up -d postgres`.
5. Run `npm install`.
6. Export the values from `.env` in your shell.
7. Run `npm run migrate`.
8. Run `npm run dev`.

The local database listens only on `127.0.0.1:54329`.
The sample database password is for local development only.

## API authentication

Every `/v1` endpoint requires:

```text
Authorization: Bearer <ZOID99_API_TOKEN>
```

`GET /health` is a process liveness check.
`GET /ready` checks database availability without exposing database details.
The browser gateway uses the operator-session endpoints with its server-only bearer credential.
The operator password never reaches browser storage, and only a hash of each random session token is persisted.

## macOS API contract

- `GET /v1/bootstrap`
- `POST /v1/ingestion`
- `GET /v1/sources/health`
- `GET /v1/connections`
- `GET /v1/connections/:provider`
- `PUT /v1/connections/:provider`
- `POST /v1/connections/:provider/validate`
- `DELETE /v1/connections/:provider`
- `GET /v1/opportunities`
- `GET /v1/opportunities/:id`
- `PATCH /v1/opportunities/:id/disposition`
- `GET /v1/watchlist`
- `POST /v1/watchlist`
- `PATCH /v1/watchlist/:id`
- `PUT /v1/watchlist`
- `DELETE /v1/watchlist/:id`
- `GET /v1/notifications`
- `PATCH /v1/notifications/:id`

Response fields and written enum values match the existing Swift models.
Bootstrap responses include an `ETag`; the macOS client sends `If-None-Match` so unchanged state returns `304 Not Modified`.
Database-only fields and encrypted values are never returned.

### Watchlist mutations

`PATCH /v1/watchlist/:id` replaces one existing entry and requires the full entry payload:

```json
{
  "kind": "Company",
  "value": "OpenAI",
  "highPriority": true
}
```

The accepted `kind` values are `Creator`, `Official source`, `Company`, `Keyword`, `Topic`, `Country`, and `Language`.
`Official source` values must be complete HTTPS URLs.
The response is `200` with the updated watchlist entry, or `404` when the UUID does not exist.

`PUT /v1/watchlist` atomically replaces the complete private user's watchlist and requires an `entries` array:

```json
{
  "entries": [
    {
      "id": "40000000-0000-4000-8000-000000000099",
      "kind": "Company",
      "value": "OpenAI",
      "highPriority": true
    }
  ]
}
```

Each entry must include its UUID, kind, value, and priority.
The server deletes entries omitted from the array, inserts new UUIDs, and updates matching UUIDs in one database transaction.
If validation or a uniqueness check fails, the transaction is rolled back and the previous watchlist remains unchanged.
Duplicate entries with the same kind and case-insensitive value return `409`.
An empty `entries` array is valid and clears the watchlist atomically.
The response is `200` with the resulting complete array of watchlist entries.

The always-on collector reads the saved watchlist at the start of every cycle.
Official source URLs use the RSS/Atom parser and retain each item URL and publication timestamp.
The server accepts only HTTPS public-network feed targets, pins an approved DNS result, revalidates redirects, and rejects responses over 2 MiB.
YouTube, X, and Instagram requests are made only when a matching server credential exists; missing credentials produce `Setup required` health with no provider request.
YouTube country and language selections become official Data API search parameters.
X language selections become recent-search query operators, while country values remain collected-evidence labels because the official recent-search API does not provide a country query operator.
Instagram creator entries use the official Business Discovery field and require both `ZOID99_INSTAGRAM_ACCOUNT_ID` and `ZOID99_INSTAGRAM_ACCESS_TOKEN`.
Social API results remain unverified evidence and cannot establish a confirmed original source.
An official API or feed that responds successfully with zero matching records remains a connected live source rather than being reported unavailable.
The Google Trends alpha path remains `Setup required` until an approved official client is supplied.

Disposition updates require `disposition`, the explicit user-action timestamp in `changedAt`, and an idempotency UUID in `mutationID`.
Repeating the same mutation is safe.
If an older offline mutation arrives after a newer action, the response returns the canonical state with the `superseded` outcome.
Save and watch remain visible in Today and Radar, while dismiss and mute are filtered by the macOS projections after reconciliation.

## Server-managed provider connections

The server connection contract supports `google-trends` and `ai-provider`.
`PUT /v1/connections/:provider` is an operator setup endpoint and accepts a credential only over the authenticated API.
The credential is persisted only after the injected provider validator confirms access.
Responses include written state, last activity, evidence, repair action, and retry time, but never include submitted, encrypted, or decrypted credentials.
The default runtime validator performs no network access and reports unavailable.
Completed connector integrations must inject their provider-specific validator and keep live checks behind an explicit opt-in environment flag.
Deleting a connection removes its encrypted credential while retaining the last known activity in the returned repair evidence.

## Production notes

Build and run the non-root multi-stage image in `Dockerfile`.
Use `compose.production.yml` as a provider-neutral release contract, not as authorization to deploy.
Validate production environment variables with `npm run config:validate` before migrations or startup.
Run migrations once before starting a new application version.
Every additive migration has a matching SQL rollback under `migrations/rollback/` that is not applied by the forward migration runner.
The 005 rollback preserves unsupported `Company` entries in `watchlist_entries_company_archive` before restoring the pre-005 constraint.
After reapplying migration 005, an operator can restore an archived row with an explicit `INSERT ... SELECT` after reviewing the archived value and timestamps.
Use a managed PostgreSQL 17 service with encrypted backups, point-in-time recovery, and required TLS.
Store the API token, database URL, and encryption key in the deployment platform's secret manager.
Store any always-on provider variables listed in `.env.production.example` in the same managed secret store and rotate them through the provider and deployment platform together.
Rotate the API token by updating the service and deployment secret manager together.
Rotating the encryption key requires decrypting and re-encrypting stored configuration in a controlled maintenance operation.
See `ops/README.md` for backup, restore, monitoring, rotation, deployment, and rollback procedures.

## YouTube credential handoff

The YouTube connector accepts either a public-data API key or a short-lived OAuth access token at runtime.
Persist API keys only through `EncryptedConfigService` under `youtube.api-key`.
Persist OAuth refresh tokens only through `EncryptedConfigService` under `youtube.oauth-refresh-token`.
Never persist access tokens when they can be refreshed, and never expose any encrypted or decrypted connector secret through `/v1` responses or logs.
The backend OAuth boundary is responsible for consent, refresh-token exchange, expiry handling, and revocation.
The macOS-only alternative stores the credential in local app preferences under the `com.zoid99.youtube-data-api` prefix.
