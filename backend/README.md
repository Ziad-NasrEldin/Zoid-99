# Zoid 99 backend

This service is the always-on data and API foundation for the single-user macOS application.
It stores normalized research records, source health, opportunities, watchlists, notifications, and encrypted connector configuration.
It intentionally does not collect from external sources.

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
The first version has one user and no public registration or session endpoint.

## macOS API contract

- `GET /v1/bootstrap`
- `GET /v1/sources/health`
- `GET /v1/opportunities`
- `GET /v1/opportunities/:id`
- `PATCH /v1/opportunities/:id/disposition`
- `GET /v1/watchlist`
- `POST /v1/watchlist`
- `DELETE /v1/watchlist/:id`
- `GET /v1/notifications`
- `PATCH /v1/notifications/:id`

Response fields and written enum values match the existing Swift models.
Database-only fields and encrypted values are never returned.

## Production notes

Run migrations once before starting a new application version.
Use a managed PostgreSQL service with encrypted backups and TLS.
Store the API token, database URL, and encryption key in the deployment platform's secret manager.
Rotate the API token by updating the service and macOS Keychain together.
Rotating the encryption key requires decrypting and re-encrypting stored configuration in a controlled maintenance operation.

## YouTube credential handoff

The YouTube connector accepts either a public-data API key or a short-lived OAuth access token at runtime.
Persist API keys only through `EncryptedConfigService` under `youtube.api-key`.
Persist OAuth refresh tokens only through `EncryptedConfigService` under `youtube.oauth-refresh-token`.
Never persist access tokens when they can be refreshed, and never expose any encrypted or decrypted connector secret through `/v1` responses or logs.
The backend OAuth boundary is responsible for consent, refresh-token exchange, expiry handling, and revocation.
The macOS-only alternative stores the credential in Keychain service `com.zoid99.youtube-data-api`.
