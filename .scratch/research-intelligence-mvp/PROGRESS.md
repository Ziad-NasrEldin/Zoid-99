Status: ready-for-agent

# Research Intelligence MVP Progress

Updated: 2026-07-24

## Product rule

Zoid 99 is a private, single-user macOS application.
It must not have app login, signup, account creation, team accounts, or an app-account system.
OAuth and connection screens exist only to authorize external providers such as YouTube, Meta, X, or another supported research provider.
Provider credentials must use macOS Keychain or encrypted server configuration as appropriate.

## Evidence standard

`integrated` means the implementation is present in the production integration branch created from baseline `79503ff`.
`active` means implementation is still underway in a named task thread.
`remaining` means no complete implementation commit was found.
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
| Always-on backend operations | integrated | Original `70806c5`, integration `6116f85`; scheduler, monitoring, secret rotation, and production configuration are deterministic-tested, while hosted Mac-sleep proof remains |
| macOS release packaging | integrated | Originals `652157a` and `deaa475`, integrations `3a65154` and `2c3e987`; universal unsigned bundle identity, centered icon, metadata, archive, and deep-link registration are verified |

No named implementation task remains active as of this update.

## All 38 user stories

| Story | State | Evidence and remaining truth |
| --- | --- | --- |
| 1. One application for all research signals | integrated | The baseline contains the shared shell and all six normalized source contracts; five provider paths still require credentials or access. |
| 2. Detect important AI developments quickly | integrated | Combined official-feed collection, bounded backend sync, strict clustering, and time-aware analysis are validated together. |
| 3. Monitor official sources | integrated | Credential-free RSS, Atom, and GitHub Releases are on main in `78986e0`; separate live connector proof was reported. |
| 4. Monitor selected US creators | integrated | YouTube and X connector contracts are integrated; no credentialed live proof is claimed. |
| 5. Monitor selected Arabic creators | integrated | YouTube, X, and Instagram connector support is integrated; editable production watchlists and live proof remain. |
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
| 22. Filter Radar by source, topic, country, language, freshness, and verification | remaining | No complete filter implementation commit found; see issue 003. |
| 23. Research a topic across connected sources | remaining | Topic surface exists, but complete cross-source query behavior was not evidenced; see issue 003. |
| 24. Save, watch, dismiss, or mute an Opportunity | integrated | Backend persistence, offline reconciliation, restart behavior, and Today/Radar projection are integrated and verified on fresh PostgreSQL. |
| 25. Manage monitoring watchlists | remaining | Local watchlist foundations exist on main, but the full editable set and provider wiring are incomplete; see issue 004. |
| 26. Send immediate high-priority alerts | integrated | Native scheduling, durable deduplication, quiet-hour deferral, and exact-opportunity deep links are integrated; macOS permission acceptance remains a live gate. |
| 27. Group lower-priority developments into digests | integrated | Grouped scheduling and durable per-opportunity history are integrated; macOS permission acceptance remains a live gate. |
| 28. Show source-connection health | integrated | The native ledger now composes real sync truth with written provider state, retained evidence, and one repair action; credentialed provider proof remains. |
| 29. Configure notification and refresh preferences | integrated | Persisted opt-in, permission truth, quiet hours, digest time, and refresh preferences are integrated and native-proofed. |
| 30. Monitor while the Mac sleeps | remaining | The server scheduler and operations package are integrated, but no production host or Mac-off collection proof has been authorized. |
| 31. Store credentials securely | integrated | Keychain and encrypted-server boundaries, validation-before-storage, removal, redacted logs, and encryption-key rotation are deterministic-tested; no live provider credential is claimed. |
| 32. Retain source links in every Research Brief | integrated | Citation enforcement and evaluation coverage are integrated with retained source links. |
| 33. Use a calm ledger interface | integrated | Main SwiftUI shell implements the Sumi-Ink ledger direction at `5aba082`; final visual acceptance remains human-reviewed. |
| 34. Pair important states with written labels | integrated | Main includes written state labels and deterministic coverage at `5aba082`. |
| 35. Support keyboard and VoiceOver workflows | remaining | No complete accessibility implementation and native acceptance report found. |
| 36. Follow macOS Reduce Motion | integrated | Shared motion policy and deterministic coverage are on main; full native QA remains in issue 010. |
| 37. Provide a Source Health Ledger | integrated | Ledger UI is on main; production evidence and repair actions depend on `200f5ee` and issue 006. |
| 38. Render Arabic research right to left | remaining | Main retains Arabic language direction signals, but full mixed Arabic-English native QA was not evidenced. |

## Next sequence

1. Complete Radar/topic research, editable monitoring controls, accessibility, RTL, and Reduce Motion acceptance through issues 003, 004, and 010.
2. Complete credentialed provider checks, macOS notification permission acceptance, hosted Mac-sleep proof, Developer ID signing, and notarization through issues 002, 006, 007, 008, 009, and 011.
3. Run the credentialed multi-day pilot in issue 012 before calling the MVP live.
