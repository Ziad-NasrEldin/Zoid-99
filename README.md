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

## Always-on backend

The production data and API foundation lives in `backend/`.
It provides PostgreSQL migrations, authenticated macOS-facing API contracts, encrypted connector configuration storage, and deterministic local setup.
The macOS ingestion worker joins the credential-free official-feed connectors to this backend.
It authenticates ingestion and bootstrap requests, persists normalized evidence and opportunities, and uses conditional refreshes when backend state has not changed.
See `backend/README.md` for environment variables and startup instructions.

## Live integration status

Credential-free RSS 2.0, Atom, and GitHub Releases connectors are available for the verified official starter catalog.
Without backend environment variables, the app uses deterministic fixtures and never presents fixture evidence as live.
Set `ZOID99_API_BASE_URL` and a matching `ZOID99_API_TOKEN` to enable scheduled official-feed collection and authenticated synchronization.
Live YouTube, Google Trends, Instagram, comments, and X credentials are not bundled.
Native notification permission is requested only through the explicit setup or settings action.
Always-on monitoring while the Mac sleeps requires a separately deployed monitoring service.

Run the opt-in public-feed validation with:

```sh
ZOID99_RUN_LIVE_FEEDS=1 swift test --filter LivePublicFeedTests

Run the opt-in full-spine smoke test against a migrated backend with:

```sh
ZOID99_RUN_LIVE_SPINE=1 \
ZOID99_API_BASE_URL=http://127.0.0.1:3000 \
ZOID99_API_TOKEN=replace-with-the-configured-token \
swift test --filter LivePublicFeedTests/testRealOfficialFeedReachesBackendAndMacOSBootstrap
```
```

The normal test suite never requires network access.

## Manual validation checklist

- Complete all five first-run steps.
- Verify every sidebar destination and shared Opportunity Detail.
- Test keyboard navigation and VoiceOver labels.
- Enable macOS Reduce Motion and confirm press scaling is removed.
- Confirm Arabic comment rows read right-to-left while controls remain left-to-right.
- Grant notification permission and send the deterministic high-priority test alert.
- Configure each real connector only with official credentials and verify its health evidence.
