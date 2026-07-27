# Opportunity Sortable List Design

## Status

Approved for implementation on 2026-07-24.

## Goal

Make the existing Live Radar opportunity ledger sortable without changing the authoritative opportunity scoring system or weakening any existing filters.

The list defaults to Total Score in descending order.
The user can switch among Total Score, Newest, High Priority, Regional Relevance, and Arabic Coverage Gap.
The selected sort survives app relaunches and can be reset immediately to Total Score.

## Product boundaries

- Keep one opportunity list.
- Preserve every existing Live Radar filter and search field.
- Do not change `ScoreBreakdown`, its inputs, or `Opportunity.isHighPriority`.
- Keep detailed score components in Opportunity Detail.
- Do not add matrices, tier boards, multi-sort builders, secondary dashboards, or new scoring abstractions.
- Keep source links, timestamps, verification state, and data-truth handling unchanged.

## User experience

Live Radar keeps its current two-row filter area.
A compact Sort picker sits on the second row after Verification and before the flexible spacer.
Its visible value always names the active sort, so the current ordering is clear without opening the menu.

The picker contains these choices in this order:

1. Total Score
2. Newest
3. High Priority
4. Regional Relevance
5. Arabic Coverage Gap

A compact Reset Sort button sits next to the picker.
It is disabled while Total Score is active and returns the list to Total Score in one action.
The existing Clear Filters button continues to clear only filters and search.
It does not reset sorting because sorting is a view preference, not a filter.

The count label continues to report the filtered result count.
Sorting changes only the order of those results.
No list transition or decorative animation is added because users may change this control frequently and immediate feedback is clearer.

## Sort semantics

All sorts are descending and deterministic.
Each non-default sort uses Total Score descending as its first tie-breaker.
Remaining ties use the latest evidence timestamp descending, then the opportunity UUID string ascending.

- Total Score compares `opportunity.score.total`.
- Newest compares the latest `publishedAt` among the opportunity's source items, falling back to `earliestPublishedAt`.
- High Priority places `Opportunity.isHighPriority == true` first.
- Regional Relevance compares `opportunity.score.regionalRelevance`.
- Arabic Coverage Gap compares `opportunity.score.arabicCoverageGap`.

These choices expose existing authoritative values.
They do not recompute, weight, normalize, or reinterpret any score component.

## State and persistence

Add a small `OpportunitySort` enum with stable raw string values and the five user-facing labels.
The enum owns the deterministic comparison used by the Live Radar list.

`AppStore` owns the active `radarSort`.
It loads the raw value from a dedicated `UserDefaults` key during initialization and falls back to Total Score when no value exists or a stored value is invalid.
Changing the sort writes the raw value immediately.
This keeps the preference independent from the research cache and allows it to survive a normal app relaunch.

Tests inject an isolated `UserDefaults` suite so they cannot alter the user's real preference.

## Data flow

`AppStore.radarOpportunities` performs the existing search and filter pass first.
It then sorts that filtered array with the active `OpportunitySort`.
No filter predicate changes.
No source data or persisted opportunity record changes.

The Reset Sort action calls one store method that sets Total Score and persists it through the same path as a picker change.

## Accessibility and visual treatment

The Sort picker uses the existing native picker treatment and SUMI-E ledger styling.
Its accessibility label is "Sort Live Radar opportunities".
The Reset Sort button has an explicit accessibility label describing the destination state.
Written labels identify both controls and the active sort, so meaning never relies on color.
The control uses the current zero-radius, ruled, black-ink interface without a new accent color or shadow.

## Error handling

An absent or unknown stored sort value safely resolves to Total Score.
An opportunity with no source items uses `earliestPublishedAt` for Newest.
Stable tie-breakers prevent rows with equal values from changing order between renders.

## Testing

Focused tests cover:

- Total Score descending, including deterministic ties.
- Newest by latest evidence timestamp.
- High Priority first while preserving Total Score order within priority groups.
- Regional Relevance descending.
- Arabic Coverage Gap descending.
- Stored sort restoration in a new `AppStore`.
- Invalid stored values falling back to Total Score.
- Reset returning to Total Score and persisting the reset.
- Every existing Live Radar filter still narrowing the list before sorting.

The full Swift test suite must pass.
The real native macOS app must show the compact control, visibly reorder opportunities for a non-default sort, preserve that sort after relaunch, and reset to Total Score.
A proof screenshot must show the active non-default sort and the reordered list.
