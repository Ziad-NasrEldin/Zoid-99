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

Live YouTube, Google Trends, Instagram, comments, official feeds, and X credentials are not bundled.
The app shows each source as `Setup required` and never presents fixture evidence as live.
Native notification permission is requested only through the explicit setup or settings action.
Always-on monitoring while the Mac sleeps requires a separately deployed monitoring service.

## Manual validation checklist

- Complete all five first-run steps.
- Verify every sidebar destination and shared Opportunity Detail.
- Test keyboard navigation and VoiceOver labels.
- Enable macOS Reduce Motion and confirm press scaling is removed.
- Confirm Arabic comment rows read right-to-left while controls remain left-to-right.
- Grant notification permission and send the deterministic high-priority test alert.
- Configure each real connector only with official credentials and verify its health evidence.
