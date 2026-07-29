# Zoid 99 production operations

## Hosting contract

The service runs as one stateless Linux container behind HTTPS.
Only the reverse proxy may reach port 8099.
The public internet may reach `/health` and `/ready`; every research route remains protected by the private bearer credential.
The web dashboard requires the single operator password and a revocable secure session cookie.
There is no signup, registration, password recovery, or multi-user account system.

The chosen container host must support restart-on-failure, rolling or blue-green releases, environment-backed secrets, persistent structured logs, and an external HTTPS uptime check.
Do not deploy this repository until the owner chooses and authorizes a host.

## PostgreSQL contract

Use PostgreSQL 17 with a dedicated database and least-privilege application role.
The database must require TLS, encrypt storage and backups, keep at least 14 daily backups, and support point-in-time recovery.
Run backups outside the application container and copy them to encrypted storage in a separate failure domain.
Test restoration into a disposable database at least monthly.

`ops/backup.sh` creates and validates a custom-format dump plus SHA-256 checksum.
`ops/restore.sh` verifies the checksum and requires the explicit `CONFIRM_RESTORE=restore-zoid99` guard.

## Deployment

1. Build the image from the immutable Git commit.
2. Scan the image and run `npm audit --omit=dev`.
3. Render `.env.production` from the host secret manager as a root-owned `0600` release file.
   The file is ignored by Git and must be deleted when the release is retired.
4. Run `npm run config:validate` inside the release image.
5. Run the one-shot migration container.
6. Start the API container without exposing port 8099 publicly.
7. Confirm `/health`, `/ready`, one authenticated `/v1/bootstrap` request, and structured log delivery.
8. Configure an external uptime check for `/ready` every minute and alert after three failures.
9. Alert on container restarts, HTTP 5xx rate, uncaught errors, PostgreSQL saturation, backup failure, and a collection cycle older than twice its configured interval.

Set `ERROR_MONITORING_WEBHOOK_URL` to an HTTPS endpoint that accepts JSON.
The application sends only service name, immutable version, event name, and timestamp for startup and collection failures.
It never includes exception messages, request bodies, credentials, or encrypted values.

## Rollback

1. Stop traffic to the failed release.
2. Start the previous immutable image with the same configuration.
3. Confirm `/ready` before restoring traffic.
4. Do not reverse a migration in place.
5. If a migration is incompatible, restore the pre-deployment backup into a new database, point the previous image at it, and preserve the failed database for investigation.

## Credential rotation

Rotate the private API credential without downtime by setting the new value as the primary credential and the old value as `ZOID99_API_TOKEN_PREVIOUS`.
Restart the backend, update the deployment secret manager, verify one authenticated request with the new value, remove the previous value, and restart again.
The previous value must exist only for the short rotation window.

Rotate the encryption key only during maintenance:

1. Take and verify a database backup.
2. Stop the API so encrypted configuration cannot change.
3. Supply the old and new 32-byte base64 keys only to the one-shot `npm run secrets:rotate-key` process.
4. Replace the runtime encryption key with the new value, restart, and verify connector configuration can be decrypted.
5. Destroy the old key only after the rollback window closes.

Provider credentials are revoked at the provider first, replaced in encrypted configuration, verified with a connector health check, and then permanently removed from the provider.
Never print credentials, shell history containing credentials, environment dumps, or encrypted configuration values.

## Collection scheduling

The backend starts `CollectionScheduler` only after the API is listening.
It immediately collects the same credential-free OpenAI News, Hugging Face Releases, and arXiv catalog used by the native client, then repeats after `COLLECTION_INTERVAL_SECONDS`.
One cycle must finish before the next begins, and one failed cycle does not stop later cycles.
Credentialed connectors remain separate work and must be registered with the server scheduler after their task commits are integrated.
Production acceptance for issue 008 remains blocked until a host choice and a live collection proof while the Mac is offline.
