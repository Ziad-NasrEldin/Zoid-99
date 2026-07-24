Status: ready-for-human

# Research Intelligence MVP Progress

Updated: 2026-07-24

## Product rule

Zoid 99 is a private, single-user macOS application.
It must not have app login, signup, account creation, team accounts, or an app-account system.
OAuth and connection screens exist only to authorize external providers such as YouTube, Meta, X, or another supported research provider.
Provider credentials must use macOS Keychain or encrypted server configuration as appropriate.

## Evidence standard

`integrated` means the implementation is present in release branch `codex/zoid-99-mvp-release-completion`, based on verified production integration `d90244f`.
`external` means the product path is implemented but final proof requires credentials, an account approval, or an authorized external host.
`remaining` means product implementation is still missing.
Tests prove deterministic behavior, not live provider functionality.
The combined baseline has live end-to-end proof for the credential-free official-feed flow through backend storage and the native Today surface.
YouTube, Google Trends, X, Instagram, and live AI analysis remain unproved with real credentials.

## Commit and task ledger

| Delivery | State | Evidence |
| --- | --- | --- |
| Backend and PostgreSQL foundation | integrated | `e6fa316`, original `7bc435c` |
| Credential-free official connectors | integrated | `78986e0`, original `269dee3` |
| Native persistence and sync boundary | integrated | `5aba082`, original `1040761` |
| Official-feed ingestion and native sync | integrated | Original `200f5ee`, baseline `f3648be`; live proof reports 90 official-feed items |
| YouTube and comments connector | integrated | Original `0663af1`, baseline `0d5c165`; credential-gated, no live results claimed |
| Analysis pipeline | integrated | Rebased input `e45dad7`, baseline `7c16bc4`; combined regressions cover bounded ingestion and strict clustering |
| Google Trends connector | integrated | Original `2195bd0`, baseline `5d7cc44`; alpha access unavailable |
| X connector | integrated | Original `958082e`, baseline `52b6133`; credential-gated |
| Instagram connector | integrated | Original `2088071`, baseline `f289edf`; credential-gated |
| Progress ledger | integrated | Original `84f3121`, baseline `a304c32`; reconciled after combined validation |
| Opportunity disposition persistence | integrated | Original `96a44b7`, integration `453c005`; Swift and fresh-PostgreSQL reconciliation tests pass |
| External provider connections and repair | integrated | Original `c4b0f4d`, integration `cd21a81`; native repair proof and secure-boundary tests pass, with no credentialed provider claimed live |
| Native notification delivery | integrated | Original `4e368fe`, integration `f933f6a`; settings, history, and packaged deep-link proof pass, while macOS permission acceptance remains |
| Always-on backend operations | integrated | Original `70806c5`, integration `6116f85`; each scheduler cycle now reads the persisted Watchlist, collects official feeds, plans every supported country/language query, gates official provider APIs on server credentials, preserves unverified social evidence truth, and retains monitoring/rotation readiness, while hosted Mac-sleep proof remains |
| macOS release packaging | integrated | Originals `652157a` and `deaa475`, integrations `3a65154` and `2c3e987`; universal unsigned bundle identity, centered icon, metadata, archive, and deep-link registration are verified |
| Radar filters and Topics research recovery | integrated | Recovered deliberately from orphaned commit `fc7ee3be6b365274823f0905ea001bcb55014ca1`; source, topic, country, language, freshness, and verification filters plus an explicit normalized connected-source query, original evidence, timestamps, and truthful empty states are covered by focused tests and native proof |
| Editable production Watchlists recovery | integrated | Recovered deliberately from orphaned commit `ccf8353bd9f69124e5f020f8fd0bf7a0a7f6d3d5`; all seven watchlist kinds, add/edit/remove, priority, persisted pending-sync truth, canonical backend pull-before-push reconciliation, connector input planning, and provider-truth labels are covered by Swift and fresh-PostgreSQL tests plus restart proof; its conflicting migration `002` was integrated as `005_watchlist_companies.sql` |
| Release 0.2.0 completion | integrated | Keyboard commands, VoiceOver actions, text-only RTL, Reduce Motion QA, source and menu-bar health, portable uptime checks, reproducible universal packaging, and native proof are complete; signing, notarization, credentialed providers, external deployment, and the real sleep/wake pilot remain external |

Detached snapshot `d760b661a49259475aed8b01798a96e833f32a15` was inspected and rejected because it contains only generated `.codegraph`, `.qa`, and old proof artifacts, with no unique tracked product behavior.
The dirty main checkout was inspected without modification.
Valid motion and accessibility ideas were retained where they matched `DESIGN.md`, `MOTION.md`, and the six-source authoritative PRD.
Conflicting changes that removed X, reduced six sources to five, made the backend optional, or eliminated always-on monitoring were explicitly rejected.

## All 38 user stories

| Story | State | Evidence and remaining truth |
| --- | --- | --- |
| 1. One application for all research signals | integrated | The baseline contains the shared shell and all six normalized source contracts; five provider paths still require credentials or access. |
| 2. Detect important AI developments quickly | integrated | Combined official-feed collection, bounded backend sync, strict clustering, and time-aware analysis are validated together. |
| 3. Monitor official sources | integrated | Credential-free RSS, Atom, and GitHub Releases are on main in `78986e0`; separate live connector proof was reported. |
| 4. Monitor selected US creators | integrated | YouTube and X connector contracts are integrated; no credentialed live proof is claimed. |
| 5. Monitor selected Arabic creators | integrated | YouTube, X, and Instagram connector support and editable production watchlists are integrated; credentialed provider proof remains external. |
| 6. Collect YouTube videos and search signals | integrated | Contract tests pass, but no YouTube credentials were available. |
| 7. Compare Google Trends countries | integrated | The official alpha provider contract is integrated, with no approved live access. |
| 8. Collect permitted Instagram references | integrated | The supported professional-account boundary is integrated, with no Meta token proof. |
| 9. Monitor X accounts and keywords | integrated | The official API connector is integrated but credential-gated and unproved live. |
| 10. Monitor product releases and trusted sources | integrated | Official feeds and GitHub Releases are on main in `78986e0`. |
| 11. Collect comments from owned accounts | integrated | YouTube and Instagram owned-comment boundaries are integrated; OAuth and live proof remain. |
| 12. Analyze reference-creator comments | integrated | Connector collection and deterministic comment grouping are combined-tested; credentialed live proof remains. |
| 13. Combine duplicates into one Story Cluster | integrated | Complete-link clustering and identifier regressions prevent unrelated releases and model versions from merging. |
| 14. Display the earliest known source | integrated | Hardened origin rules and original-source retention are combined-tested. |
| 15. Mark claims confirmed, disputed, or unverified | integrated | Hardened evidence rules and written states are combined-tested. |
| 16. Timestamp every Opportunity | integrated | Main models and views retain publication and collection timestamps at `5aba082`. |
| 17. Score freshness and momentum | integrated | Time-aware deterministic scoring is integrated. |
| 18. Show an Arabic coverage-gap signal | integrated | Evidence-backed Arabic coverage-gap analysis is integrated. |
| 19. Explain Egypt and Gulf relevance | integrated | Regional evidence for Egypt, Saudi Arabia, UAE, and Oman is integrated; live AI evaluation remains credential-gated. |
| 20. Show a daily Today briefing | integrated | Native proof shows 88 live official-feed opportunities in Today with durable cached state. |
| 21. Show a chronological Live Radar | integrated | Radar is integrated; complete live multi-source data still depends on provider credentials. |
| 22. Filter Radar by source, topic, country, language, freshness, and verification | integrated | Recovered commit `fc7ee3b` was ported deliberately and reconciled with current state; focused tests and `docs/proof/release-0.2.0-radar-filters.jpeg` prove all required controls. |
| 23. Research a topic across connected sources | integrated | The explicit research action refreshes configured official providers through the normalized connector contract, merges original evidence, retains links and timestamps, and distinguishes prompt, no matches, and missing data; focused tests and evidence/empty-state screenshots prove the visible flow. |
| 24. Save, watch, dismiss, or mute an Opportunity | integrated | Backend persistence, offline reconciliation, restart behavior, and Today/Radar projection are integrated and verified on fresh PostgreSQL. |
| 25. Manage monitoring watchlists | integrated | Recovered commit `ccf8353` was ported deliberately with migration renumbered to `005`; all seven kinds support validated add/edit/remove, priority, persisted offline mutations, canonical backend pull-before-push reconciliation, connector inputs for each officially supported provider query, and truthful unsupported or collected-evidence labels. |
| 26. Send immediate high-priority alerts | integrated | Native scheduling, durable deduplication, quiet-hour deferral, and exact-opportunity deep links are integrated; macOS permission acceptance remains a live gate. |
| 27. Group lower-priority developments into digests | integrated | Grouped scheduling and durable per-opportunity history are integrated; macOS permission acceptance remains a live gate. |
| 28. Show source-connection health | integrated | The native ledger now composes real sync truth with written provider state, retained evidence, and one repair action; credentialed provider proof remains. |
| 29. Configure notification and refresh preferences | integrated | Persisted opt-in, permission truth, quiet hours, digest time, and refresh preferences are integrated and native-proofed. |
| 30. Monitor while the Mac sleeps | external | The backend scheduler reads the persisted Watchlist and runs fixed and user-selected official/provider collection independently of the Mac app; health, readiness, backup/restore, deployment, rollback, and monitoring paths are implemented, while a real reachable production host and authorized sleep/wake pilot are still required. |
| 31. Store credentials securely | integrated | Keychain and encrypted-server boundaries, validation-before-storage, removal, redacted logs, and encryption-key rotation are deterministic-tested; no live provider credential is claimed. |
| 32. Retain source links in every Research Brief | integrated | Citation enforcement and evaluation coverage are integrated with retained source links. |
| 33. Use a calm ledger interface | integrated | Main SwiftUI shell implements the Sumi-Ink ledger direction at `5aba082`; final visual acceptance remains human-reviewed. |
| 34. Pair important states with written labels | integrated | Main includes written state labels and deterministic coverage at `5aba082`. |
| 35. Support keyboard and VoiceOver workflows | integrated | Command-1 through Command-7 navigation, Command-F search, Command-R refresh, meaningful labels, actions, values, and edit/remove descriptions are implemented, tested, and inspected through the native accessibility tree. |
| 36. Follow macOS Reduce Motion | integrated | Shared motion policy gates press motion, the launched packaged app truthfully reports the current system setting, and native proof covers the Reduce Motion enabled state. |
| 37. Provide a Source Health Ledger | integrated | The native ledger and menu-bar item show six-source health, last refresh, cached/live truth, and one refresh or repair action; deterministic and native proof are complete, while credentialed source checks remain external. |
| 38. Render Arabic research right to left | integrated | Arabic research text is right to left while mixed evidence and application controls keep their correct order; deterministic coverage and native proof are complete. |

## Release 0.2.0 validation record

Swift completed 84 tests with 79 passed, 5 explicit opt-in live skips, and 0 failures.
The release Swift build passed.
The credential-free live official-feed check passed and collected 30 OpenAI News, 30 Hugging Face Releases, and 30 arXiv items.
Backend check, build, and audit passed with 0 high-severity vulnerabilities.
Backend completed 46 tests with 39 passed and 7 PostgreSQL skips in the ordinary suite.
All 46 backend tests passed against a fresh PostgreSQL database after migrations `001` through `005`.
Rollback migrations `003` through `005` ran in reverse order, migration `005` archived an existing Company row, all three reapplied successfully, and all 46 tests then passed with zero skips.
Outbound official-source collection rejects private, loopback, link-local, and non-HTTPS targets, revalidates every redirect with pinned public DNS, caps response size, and distinguishes a healthy zero-result response from an unavailable source.
A custom-format PostgreSQL backup was checksummed and restored into a fresh database with all five migrations.
Health, readiness, authenticated bootstrap, portable uptime checks, and a 45-second local always-on observation passed.
Shellcheck, Zsh syntax, credential scan, conflict scan, `git diff --check`, bundle metadata, deep link, and universal architecture verification passed.
The arm64 and x86_64 package was built twice with identical SHA-256 `9ab0046c0af9b9da09914276786d4421f767976f98579df225c7ea401dc58c06`.
The unsigned artifact is `.build/release-artifacts/Zoid-99-0.2.0-unsigned.zip`.
The final packaged application launched successfully.

## Next sequence

1. Provide approved YouTube, owned YouTube OAuth/comments, Google Trends alpha, X, Instagram/Meta, AI, and production-backend credentials for opt-in live validation.
2. Authorize a production host and PostgreSQL target, then run real deploy, rollback, monitoring, and Mac sleep/wake proof against its reachable URL.
3. Provide a Developer ID Application identity and notary Keychain profile, install the signed build, accept notification permission, and validate the notification deep link.
4. Run the credentialed multi-day pilot in issue 012 before calling the MVP live.
