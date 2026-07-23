Status: ready-for-agent

# Research Intelligence MVP Progress

Updated: 2026-07-24

## Product rule

Zoid 99 is a private, single-user macOS application.
It must not have app login, signup, account creation, team accounts, or an app-account system.
OAuth and connection screens exist only to authorize external providers such as YouTube, Meta, X, or another supported research provider.
Provider credentials must use macOS Keychain or encrypted server configuration as appropriate.

## Evidence standard

`integrated` means the implementation is on `main` at `5aba082`.
`implemented-but-not-integrated` means a named task commit exists locally but is not on `main`.
`active` means implementation is still underway in a named task thread.
`remaining` means no complete implementation commit was found.
Tests prove deterministic behavior, not live provider functionality.
The only live end-to-end proof found in wave two is the credential-free official-feed flow in `200f5ee`.
YouTube, Google Trends, X, Instagram, and live AI analysis remain unproved with real credentials.

## Commit and task ledger

| Delivery | State | Evidence |
| --- | --- | --- |
| Backend and PostgreSQL foundation | integrated | `e6fa316`, original `7bc435c` |
| Credential-free official connectors | integrated | `78986e0`, original `269dee3` |
| Native persistence and sync boundary | integrated | `5aba082`, original `1040761` |
| Official-feed ingestion and native sync | implemented-but-not-integrated | `200f5ee`, thread `019f90d4-761c-7a10-8555-c07131543451`; live proof reports 90 official-feed items |
| YouTube and comments connector | implemented-but-not-integrated | `0663af1`, thread `019f90d4-9ef4-7a61-ba8a-c7d2a125c1ae`; credential-gated, no live results claimed |
| Analysis pipeline | implemented-but-not-integrated | `8db1159`, thread `019f90d4-c184-7bf3-9dd6-bd3f2d86b243`; deterministic evaluation only |
| Google Trends connector | implemented-but-not-integrated | `2195bd0`, thread `019f90d5-3997-78f2-ab5c-8faffbf2b28a`; alpha access unavailable |
| X connector | implemented-but-not-integrated | `958082e`, thread `019f90d5-58c2-7581-887a-35a6b40fc666`; credential-gated |
| Instagram connector | implemented-but-not-integrated | `2088071`, thread `019f90d5-785f-7060-ada7-60e49f02e793`; credential-gated |

No named implementation task remains active as of this update.

## All 38 user stories

| Story | State | Evidence and remaining truth |
| --- | --- | --- |
| 1. One application for all research signals | implemented-but-not-integrated | Main has the shared shell at `5aba082`; the six-source production path depends on integrating `200f5ee`, `0663af1`, `2195bd0`, `958082e`, and `2088071`. |
| 2. Detect important AI developments quickly | implemented-but-not-integrated | Collection/sync is in `200f5ee` and time-aware analysis is in `8db1159`; neither is on main. |
| 3. Monitor official sources | integrated | Credential-free RSS, Atom, and GitHub Releases are on main in `78986e0`; separate live connector proof was reported. |
| 4. Monitor selected US creators | implemented-but-not-integrated | YouTube monitoring is in `0663af1`; X monitoring is in `958082e`; no credentialed live proof. |
| 5. Monitor selected Arabic creators | implemented-but-not-integrated | Provider connector support exists in `0663af1`, `958082e`, and `2088071`; editable production watchlists and live proof remain. |
| 6. Collect YouTube videos and search signals | implemented-but-not-integrated | `0663af1`; contract tests passed, but no YouTube credentials were available. |
| 7. Compare Google Trends countries | implemented-but-not-integrated | `2195bd0`; official alpha provider contract only, with no approved live access. |
| 8. Collect permitted Instagram references | implemented-but-not-integrated | `2088071`; supported professional-account boundary only, with no Meta token proof. |
| 9. Monitor X accounts and keywords | implemented-but-not-integrated | `958082e`; official API connector is credential-gated and unproved live. |
| 10. Monitor product releases and trusted sources | integrated | Official feeds and GitHub Releases are on main in `78986e0`. |
| 11. Collect comments from owned accounts | implemented-but-not-integrated | YouTube owned-comment boundary is in `0663af1`; Instagram owned comments are in `2088071`; OAuth and live proof remain. |
| 12. Analyze reference-creator comments | implemented-but-not-integrated | Collection is in `0663af1` and `2088071`; deterministic grouping exists in `8db1159`; no combined or live proof. |
| 13. Combine duplicates into one Story Cluster | implemented-but-not-integrated | A basic deterministic pipeline is on main; production hardening is in `8db1159` and must be integrated and combined-tested. |
| 14. Display the earliest known source | implemented-but-not-integrated | Main retains original-source metadata; stronger origin rules are in `8db1159` and combined UI proof remains. |
| 15. Mark claims confirmed, disputed, or unverified | implemented-but-not-integrated | Written states exist on main; hardened evidence rules are in `8db1159`. |
| 16. Timestamp every Opportunity | integrated | Main models and views retain publication and collection timestamps at `5aba082`. |
| 17. Score freshness and momentum | implemented-but-not-integrated | Basic scoring exists on main; time-aware scoring is in `8db1159`. |
| 18. Show an Arabic coverage-gap signal | implemented-but-not-integrated | Basic projection exists on main; evidence-backed analysis is in `8db1159`. |
| 19. Explain Egypt and Gulf relevance | implemented-but-not-integrated | Regional evidence for Egypt, Saudi Arabia, UAE, and Oman is in `8db1159`; no live AI evaluation. |
| 20. Show a daily Today briefing | integrated | Today view and durable cached state are on main at `5aba082`; real official-feed delivery awaits `200f5ee`. |
| 21. Show a chronological Live Radar | integrated | Radar view is on main at `5aba082`; complete live multi-source data awaits connector integration. |
| 22. Filter Radar by source, topic, country, language, freshness, and verification | remaining | No complete filter implementation commit found; see issue 003. |
| 23. Research a topic across connected sources | remaining | Topic surface exists, but complete cross-source query behavior was not evidenced; see issue 003. |
| 24. Save, watch, dismiss, or mute an Opportunity | integrated | Local durable dispositions are on main in `5aba082`; backend persistence remains in issue 005. |
| 25. Manage monitoring watchlists | remaining | Local watchlist foundations exist on main, but the full editable set and provider wiring are incomplete; see issue 004. |
| 26. Send immediate high-priority alerts | implemented-but-not-integrated | Native scheduling, permission truth, durable deduplication, and deep-link handling are implemented on issue 007; final OS-permission acceptance remains. |
| 27. Group lower-priority developments into digests | implemented-but-not-integrated | Digest decisions now schedule as one grouped native notification with durable per-opportunity history; final OS-permission acceptance remains. |
| 28. Show source-connection health | implemented-but-not-integrated | Source Health Ledger is on main; real sync truth is in `200f5ee`; repair workflows remain. |
| 29. Configure notification and refresh preferences | implemented-but-not-integrated | Issue 007 adds persisted opt-in, permission state, quiet hours, and digest time; user confirmation of preferred hours remains. |
| 30. Monitor while the Mac sleeps | remaining | `200f5ee` explicitly runs only while the app is open; always-on hosting is unresolved. |
| 31. Store credentials securely | remaining | Connector contracts document Keychain/encrypted-server boundaries, but production secret storage and rotation are not complete. |
| 32. Retain source links in every Research Brief | implemented-but-not-integrated | Main retains source links; `8db1159` adds citation enforcement and evaluation coverage. |
| 33. Use a calm ledger interface | integrated | Main SwiftUI shell implements the Sumi-Ink ledger direction at `5aba082`; final visual acceptance remains human-reviewed. |
| 34. Pair important states with written labels | integrated | Main includes written state labels and deterministic coverage at `5aba082`. |
| 35. Support keyboard and VoiceOver workflows | remaining | No complete accessibility implementation and native acceptance report found. |
| 36. Follow macOS Reduce Motion | integrated | Shared motion policy and deterministic coverage are on main; full native QA remains in issue 010. |
| 37. Provide a Source Health Ledger | integrated | Ledger UI is on main; production evidence and repair actions depend on `200f5ee` and issue 006. |
| 38. Render Arabic research right to left | remaining | Main retains Arabic language direction signals, but full mixed Arabic-English native QA was not evidenced. |

## Next sequence

1. Integrate and combined-test the six completed task commits through issue 001.
2. Build provider-only connection UI and editable monitoring controls through issues 002 to 004.
3. Complete persistence, repair, notifications, hosting, security, accessibility, and release work through issues 005 to 011.
4. Run the credentialed multi-day pilot in issue 012 before calling the MVP live.
