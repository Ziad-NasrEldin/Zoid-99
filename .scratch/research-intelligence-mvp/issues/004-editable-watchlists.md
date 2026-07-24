Status: ready-for-human

# Complete editable monitoring watchlists

Support creators, official sources, companies, keywords, topics, countries, and languages.
Persist edits and priorities, then feed them into each supported connector.
Label provider-specific unsupported entries instead of silently dropping them.

## Completion evidence

Recovered orphaned commit `ccf8353bd9f69124e5f020f8fd0bf7a0a7f6d3d5` was reviewed and ported deliberately against integration `d90244f`.
Its conflicting migration number was reconciled as `backend/migrations/005_watchlist_companies.sql`.
Swift and fresh-PostgreSQL tests cover all seven kinds, validation, add, edit, remove, priority, persisted offline mutations, canonical backend pull-before-push reconciliation, provider connector inputs, and provider-specific capability truth.
The always-on backend rereads the canonical Watchlist each cycle, preserves every supported country/language provider plan, uses only official APIs, makes no credentialless request, and keeps social evidence unverified.
Rollback 005 archives Company rows before restoring the old database constraint, and its PostgreSQL regression passes.
The packaged 0.2.0 app was restarted after an edit and retained `Final Release QA Edited` with high priority.
Native proof is stored in `docs/proof/release-0.2.0-watchlist-add.jpeg`, `docs/proof/release-0.2.0-watchlist-edit.jpeg`, and `docs/proof/release-0.2.0-watchlist-persistence.jpeg`.
