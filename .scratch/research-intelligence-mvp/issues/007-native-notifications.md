Status: ready-for-human

# Complete native alerts and digests

Implement notification permission, immediate alerts, digests, quiet hours, deep links, and menu-bar status.
Preserve the analysis pipeline's alert versus digest decision.
User input is required for quiet hours and urgency preferences before final acceptance.

## Implemented

- Native macOS permission and delivery adapter with explicit opt-in
- Immediate high-priority alerts and grouped lower-priority digests
- Configurable quiet hours and digest time with safe defaults
- Durable delivery history, restart-safe deduplication, and truthful failures
- Notification and history deep links into Opportunity Detail
- Deterministic tests and disposable manual proof mode

## Human acceptance remaining

- Confirm the preferred quiet-hours and digest schedule
- Grant macOS notification permission in a packaged build
- Click the native test alert and confirm the Opportunity Detail destination
