# Zoid 99

Native macOS SwiftUI research intelligence MVP.

## Run

```sh
swift run Zoid99
```

The first run uses deterministic fixtures for all six source groups.
Complete setup to enter the main research ledger.

## Test

```sh
swift test
```

## macOS release build

Build and verify a credential-free unsigned application bundle with:

```sh
./scripts/build-release.sh
./scripts/verify-release.sh ".build/release-artifacts/Zoid 99.app"
```

Signing, hardened runtime, notarization, and update-delivery instructions are in [docs/RELEASING.md](docs/RELEASING.md).

## Always-on backend

The production data and API foundation lives in `backend/`.
It provides PostgreSQL migrations, authenticated macOS-facing API contracts, encrypted connector configuration storage, and deterministic local setup.
The macOS ingestion worker joins the credential-free official-feed connectors to this backend.
It authenticates ingestion and bootstrap requests, persists normalized evidence and opportunities, and uses conditional refreshes when backend state has not changed.

The server also supports collection of the verified credential-free official catalog, a non-overlapping scheduler, a hardened container, and executable operations workflows.
Credentialed provider collectors remain separate work and are not presented as live.
See `backend/README.md` for environment variables and startup instructions.

## Live integration status

Credential-free RSS 2.0, Atom, and GitHub Releases connectors are available for the verified official starter catalog.
Without backend environment variables, the app uses deterministic fixtures and never presents fixture evidence as live.
Set `ZOID99_API_BASE_URL` and a matching `ZOID99_API_TOKEN` to enable scheduled official-feed collection and authenticated synchronization.
Production YouTube Data API collection supports monitored reference and owned channels, recent uploads, keyword search, and video comments.
Public reference-channel reads use an API key.
Owned-channel discovery with `mine=true` requires OAuth 2.0 authorization.
Public comments from a known owned or reference video can use an API key.
Credentials are supplied at runtime and are never bundled.
Store desktop credentials in macOS Keychain under service `com.zoid99.youtube-data-api`, or hand them to the backend encrypted configuration service using `youtube.api-key` and `youtube.oauth-refresh-token`.
The backend must exchange refresh tokens for short-lived access tokens and must never return refresh tokens through its public API.
Search country values use ISO 3166-1 alpha-2 codes such as `EG`, `SA`, and `US`; language values use YouTube relevance-language codes such as `ar` and `en`.
Creator watchlist values for YouTube must be stable channel IDs beginning with `UC`, not mutable display names or handles.
Live Google Trends, Instagram, and X credentials are not bundled.
Native notification permission is requested only through the explicit setup or settings action.
Always-on monitoring while the Mac sleeps requires a separately deployed monitoring service.

When the backend is available, set `ZOID99_BACKEND_URL` and `ZOID99_API_TOKEN` before launching the app.
Opportunity actions are applied immediately, retained across restarts, and retried through the private single-user API.
The app shows a written synced or queued state and does not require a Zoid 99 login.

Run the opt-in public-feed validation with:

```sh
ZOID99_RUN_LIVE_FEEDS=1 swift test --filter LivePublicFeedTests
```

Run the opt-in full-spine smoke test against a migrated backend with:

```sh
ZOID99_RUN_LIVE_SPINE=1 \
ZOID99_API_BASE_URL=http://127.0.0.1:3000 \
ZOID99_API_TOKEN=replace-with-the-configured-token \
swift test --filter LivePublicFeedTests/testRealOfficialFeedReachesBackendAndMacOSBootstrap
```

Run the opt-in YouTube validation without printing credentials:

```sh
ZOID99_RUN_LIVE_YOUTUBE=1 \
ZOID99_YOUTUBE_API_KEY='[secure value]' \
ZOID99_YOUTUBE_CHANNEL_ID='UC...' \
swift test --filter LiveYouTubeDataTests
```

The command prints only whether a channel was configured, mapped item count, quota units, and collection time.
If the key or channel ID is absent, it proves the written setup-required state and skips network access.
Normal tests use deterministic fixtures and never require a YouTube credential.

The normal test suite never requires network access.

## External provider connections

Zoid 99 has no login, signup, account creation, team account, or app-account system.
Connection screens authorize external research providers only.
YouTube, Instagram/Meta, and X credentials use macOS Keychain when the native connector owns authorization.
Google Trends and AI provider credentials are accepted only by the monitoring server and are encrypted before persistence.
Official feeds require no account.
Every provider remains setup required, unavailable, unsupported, delayed, rate limited, cached, or disconnected until its connector supplies verified evidence.
Connector-specific live checks remain explicit opt-in tests and are never part of the normal fixture suite.

## Manual validation checklist

- Complete all five first-run steps.
- Verify every sidebar destination and shared Opportunity Detail.
- Test keyboard navigation and VoiceOver labels.
- Enable macOS Reduce Motion and confirm press scaling is removed.
- Confirm Arabic comment rows read right-to-left while controls remain left-to-right.
- Grant notification permission and send the deterministic high-priority test alert.
- Configure each real connector only with official credentials and verify its health evidence.

Notification permission and native delivery are never exercised by the automated suite.
To launch a disposable, deterministic notification proof state from a packaged `.app`, set `ZOID99_MANUAL_NOTIFICATION_PROOF=1` for that launch.
The proof mode writes only to the temporary directory and does not use the normal Zoid 99 research cache.
Permission must still be granted manually from the in-app button.
