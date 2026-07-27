# Opportunity Sortable List Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a compact, persistent sort control to the existing Live Radar opportunity list without changing scoring or filtering.

**Architecture:** A focused `OpportunitySort` enum owns deterministic ordering over existing `Opportunity` values.
`AppStore` loads and saves the selected raw value through injected `UserDefaults`, applies filters before sorting, and exposes explicit select/reset methods.
`RadarView` binds a native picker and reset button to those methods.

**Tech Stack:** Swift 5.10, SwiftUI, Combine, Foundation `UserDefaults`, XCTest

## Global Constraints

- Default to Total Score descending.
- Provide Total Score, Newest, High Priority, Regional Relevance, and Arabic Coverage Gap.
- Preserve every current Live Radar filter.
- Do not change `ScoreBreakdown`, `Opportunity.isHighPriority`, or Opportunity Detail.
- Persist the selected sort across app relaunches.
- Reset returns to Total Score.
- Keep one list and add no matrix, tier board, multi-sort builder, or scoring abstraction.
- Use the existing SUMI-E visual system and no decorative list animation.

---

### Task 1: Deterministic opportunity ordering and persistence

**Files:**

- Create: `Sources/Zoid99/OpportunitySort.swift`
- Modify: `Sources/Zoid99/AppStore.swift`
- Test: `Tests/Zoid99Tests/OpportunitySortTests.swift`

**Interfaces:**

- Consumes: `Opportunity.score`, `Opportunity.isHighPriority`, `Opportunity.items`, and `Opportunity.earliestPublishedAt`.
- Produces: `OpportunitySort`, `OpportunitySort.sorted(_:)`, `AppStore.radarSort`, `AppStore.setRadarSort(_:)`, and `AppStore.resetRadarSort()`.

- [ ] **Step 1: Write focused failing tests**

Create test opportunities with controlled totals, latest timestamps, priority states, regional relevance, Arabic coverage gaps, and UUIDs.
Assert each of the five modes is descending with Total Score, newest evidence, and UUID tie-breakers.
Construct stores with an isolated `UserDefaults` suite and assert restoration, invalid-value fallback, reset, and filter-then-sort behavior.

```swift
func testNewestUsesLatestEvidenceTimestamp() {
    XCTAssertEqual(
        OpportunitySort.newest.sorted([older, newer]).map(\.id),
        [newer.id, older.id]
    )
}

@MainActor
func testSortPersistsResetsAndFiltersBeforeOrdering() {
    let defaults = UserDefaults(suiteName: suiteName)!
    store.setRadarSort(.regionalRelevance)
    XCTAssertEqual(defaults.string(forKey: OpportunitySort.storageKey), "regionalRelevance")
    XCTAssertEqual(relaunched.radarSort, .regionalRelevance)
    store.radarLanguage = "ar"
    XCTAssertTrue(store.radarOpportunities.allSatisfy {
        $0.items.contains { $0.language == "ar" }
    })
    store.resetRadarSort()
    XCTAssertEqual(store.radarSort, .totalScore)
}
```

- [ ] **Step 2: Run the focused tests and verify failure**

Run:

```sh
swift test --filter OpportunitySortTests
```

Expected: compilation fails because `OpportunitySort` and the store sort API do not exist.

- [ ] **Step 3: Implement the minimal deterministic sorter**

Create a `String`, `CaseIterable`, `Identifiable`, `Sendable` enum.
Compare the selected primary value descending, then Total Score descending for non-default modes, then latest evidence descending, then UUID string ascending.

```swift
enum OpportunitySort: String, CaseIterable, Identifiable, Sendable {
    case totalScore
    case newest
    case highPriority
    case regionalRelevance
    case arabicCoverageGap

    static let storageKey = "liveRadar.opportunitySort"
    var id: Self { self }
    var title: String {
        switch self {
        case .totalScore: "Total Score"
        case .newest: "Newest"
        case .highPriority: "High Priority"
        case .regionalRelevance: "Regional Relevance"
        case .arabicCoverageGap: "Arabic Coverage Gap"
        }
    }
    func sorted(_ opportunities: [Opportunity]) -> [Opportunity] {
        opportunities.sorted(by: areInIncreasingOrder)
    }
}
```

- [ ] **Step 4: Load, save, apply, and reset the sort in `AppStore`**

Inject `UserDefaults`, load a valid raw value or Total Score in `init`, sort the already filtered results, and persist through one setter.

```swift
@Published private(set) var radarSort: OpportunitySort
private let sortDefaults: UserDefaults

func setRadarSort(_ sort: OpportunitySort) {
    radarSort = sort
    sortDefaults.set(sort.rawValue, forKey: OpportunitySort.storageKey)
}

func resetRadarSort() {
    setRadarSort(.totalScore)
}
```

- [ ] **Step 5: Run focused tests**

Run:

```sh
swift test --filter OpportunitySortTests
```

Expected: all `OpportunitySortTests` pass.

- [ ] **Step 6: Commit the ordering and state layer**

```sh
git add Sources/Zoid99/OpportunitySort.swift Sources/Zoid99/AppStore.swift Tests/Zoid99Tests/OpportunitySortTests.swift
git commit -m "feat: add persistent opportunity sorting"
```

### Task 2: Compact Live Radar sort controls

**Files:**

- Modify: `Sources/Zoid99/Views.swift`
- Modify: `Tests/Zoid99Tests/OpportunitySortTests.swift`

**Interfaces:**

- Consumes: `AppStore.radarSort`, `setRadarSort(_:)`, and `resetRadarSort()`.
- Produces: visible Sort picker and Reset Sort button in the existing Live Radar filter area.

- [ ] **Step 1: Add a failing source-facing assertion**

Add a focused test that verifies the five labels remain stable and ordered for the picker.

```swift
func testPickerLabelsAreStableAndComplete() {
    XCTAssertEqual(
        OpportunitySort.allCases.map(\.title),
        ["Total Score", "Newest", "High Priority", "Regional Relevance", "Arabic Coverage Gap"]
    )
}
```

- [ ] **Step 2: Run the focused test**

Run:

```sh
swift test --filter OpportunitySortTests/testPickerLabelsAreStableAndComplete
```

Expected: fail until the exhaustive label implementation is complete.

- [ ] **Step 3: Add the compact picker and reset button**

Place the controls after Verification and before the spacer.
Use an explicit binding because the store property is read-only outside the store.

```swift
RadarFilterPicker(
    "Sort",
    selection: Binding(
        get: { store.radarSort },
        set: { store.setRadarSort($0) }
    )
) {
    ForEach(OpportunitySort.allCases) { sort in
        Text(sort.title).tag(sort)
    }
}
.accessibilityLabel("Sort Live Radar opportunities")

Button("Reset sort") { store.resetRadarSort() }
    .buttonStyle(SumiButtonStyle())
    .disabled(store.radarSort == .totalScore)
    .accessibilityLabel("Reset sort to Total Score")
```

- [ ] **Step 4: Run focused and full Swift tests**

Run:

```sh
swift test --filter OpportunitySortTests
swift test
```

Expected: all focused and full Swift tests pass.

- [ ] **Step 5: Commit the native controls**

```sh
git add Sources/Zoid99/Views.swift Tests/Zoid99Tests/OpportunitySortTests.swift
git commit -m "feat: add Live Radar sort controls"
```

### Task 3: Native verification and proof

**Files:**

- Create: `docs/proof/opportunity-sortable-list.jpeg`

**Interfaces:**

- Consumes: the debug or packaged native Zoid 99 app.
- Produces: native behavior evidence and screenshot proof.

- [ ] **Step 1: Build and launch the real native app**

Run:

```sh
swift build
open .build/debug/Zoid99
```

Expected: Zoid 99 launches to its persisted local research state.

- [ ] **Step 2: Verify sorting, filtering, persistence, and reset**

Open Live Radar.
Choose Arabic Coverage Gap and confirm the visible first rows differ from Total Score ordering.
Apply an existing filter and confirm the active sort remains visible and the filtered subset stays ordered.
Quit and relaunch the app and confirm Arabic Coverage Gap remains active.
Use Reset Sort and confirm Total Score becomes active.

- [ ] **Step 3: Capture proof**

Return to Arabic Coverage Gap and save a screenshot showing the compact active sort control and visibly reordered opportunity rows to `docs/proof/opportunity-sortable-list.jpeg`.

- [ ] **Step 4: Run release-proportional validation**

Run:

```sh
swift test
npm --prefix backend test
git diff --check
git status --short
```

Expected: both full suites pass, the diff has no whitespace errors, and only intended proof or plan files remain uncommitted.

- [ ] **Step 5: Commit proof and plan**

```sh
git add docs/superpowers/plans/2026-07-24-opportunity-sortable-list.md docs/proof/opportunity-sortable-list.jpeg
git commit -m "test: verify native opportunity sorting"
```
