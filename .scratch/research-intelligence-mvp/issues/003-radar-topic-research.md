Status: ready-for-human

# Complete Radar filters and topic research

Implement source, topic, country, language, freshness, and verification filters.
Make Topics query all connected sources through the normalized research contract.
Keep missing data distinct from zero results.
Retain source links and timestamps in every result and detail transition.

## Completion evidence

Recovered orphaned commit `fc7ee3be6b365274823f0905ea001bcb55014ca1` was reviewed and ported deliberately against integration `d90244f`.
Focused Swift tests cover every filter, the explicit normalized connected-source query, direct evidence matching, original links, timestamps, and distinct prompt, no-match, and missing-data states.
Native proof is stored in `docs/proof/release-0.2.0-radar-filters.jpeg`, `docs/proof/release-0.2.0-topics-evidence.jpeg`, and `docs/proof/release-0.2.0-topics-empty.jpeg`.
