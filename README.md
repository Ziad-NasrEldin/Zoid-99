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
It does not include source connectors.
See `backend/README.md` for environment variables and startup instructions.

## Live integration status

Credential-free RSS 2.0, Atom, and GitHub Releases connectors are available for the verified official starter catalog.
The current app screen still uses deterministic fixtures and never presents fixture evidence as live.
Live YouTube, Google Trends, Instagram, comments, and X credentials are not bundled.
Native notification permission is requested only through the explicit setup or settings action.
Always-on monitoring while the Mac sleeps requires a separately deployed monitoring service.

Run the opt-in public-feed validation with:

```sh
ZOID99_RUN_LIVE_FEEDS=1 swift test --filter LivePublicFeedTests
```

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
