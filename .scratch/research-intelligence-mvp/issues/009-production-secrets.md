Status: needs-info

# Secure production credentials

Store provider credentials in local app preferences or encrypted server configuration according to the provider boundary.
Add rotation and revocation paths without logging secrets.
Provider credentials and hosting configuration are required for live verification.

## Release 0.2.0 evidence

Encrypted server-secret storage, local preference boundaries, rotation, revocation, redaction, credential scanning, and credential-free fallback behavior are implemented and deterministic-tested.
No credential was exposed or committed.

## External blocker

Provider credentials, the production backend base URL and token, and the production encryption key are required for credentialed rotation and revocation proof.
