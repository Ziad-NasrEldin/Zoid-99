# Zoid 99 Visual Quality Audit

## Outcome

Phase 1 was completed and visually verified before phase 2 began.
The established Sumi-e ink system remained authoritative.
No product feature, publishing workflow, or accepted research behavior was added or removed.

## Before and after

| Before | After | Why |
| --- | --- | --- |
| Comments showed a blank page when no clusters existed. | Comments shows a bordered Sumi-e empty state with a clear next action. | Every legitimate data state needs a visible, understandable result. |
| Live Radar forced filters, sorting, count, and actions into one compressed row at the minimum window. | Filters and sort actions use deliberate rows that preserve full labels and hit targets. | Controls must remain readable and discoverable at the supported minimum. |
| Topic research controls compressed the query placeholder and status into clipped fragments. | `ViewThatFits` selects a compact stacked control layout when horizontal space is limited. | Adaptive layout preserves meaning without device-specific width hacks. |
| Six source-coverage cards stayed in one rigid row. | An adaptive grid reflows the cards while retaining the Sumi ledger treatment. | Source state remains readable through window resizing. |
| Sidebar status was truncated to one line. | Status can use two lines without changing the sidebar hierarchy. | The outcome text is operationally important and must remain visible. |
| Opened notification rows inherited unreadably faint disabled styling. | The row remains non-interactive while its label keeps normal Sumi contrast. | Disabled behavior should not erase historical information. |

## Window matrix

The actual minimum content size is 980 by 680 points.
The native screenshots include the macOS title bar, so minimum captures are 980 by 732 pixels on the current display.
The maximized native captures are 1351 by 768 pixels on the current display.
Intermediate medium and standard widths were checked during the live resize sweep between these two verified extremes.

| Surface | Compact 980 x 680 | Medium resize sweep | Standard desktop | Large / maximized | States and overlays |
| --- | --- | --- | --- | --- | --- |
| Today | Pass | Pass | Pass | Pass | Populated ledger, refresh action, metrics, long titles |
| Live Radar | Pass | Pass | Pass | Pass | Search, all filters, sort, reset, clear, sort menu, long rows |
| Topics | Pass | Pass | Pass | Pass | Prompt state, disabled research action, source coverage grid |
| Comments | Pass | Pass | Pass | Pass | Empty state and RTL-aware row implementation |
| Watchlists | Pass | Pass | Pass | Pass | Form, filter strip, rows, priority, edit and remove actions |
| Notifications | Pass | Pass | Pass | Pass | Permission state, disabled test action, opened and unread rows |
| Sources & Settings | Pass | Pass | Pass | Pass | Long scrolling content, forms, disabled controls, provider actions |
| Opportunity Detail | Pass | Pass | Pass | Pass | Long title, evidence, score ledger, actions, scrolling sheet |
| Sidebar and status | Pass | Pass | Pass | Pass | Selected state, two-line status, keyboard destinations |

## Accessibility and localization

Keyboard shortcuts and focus behavior remain unchanged.
VoiceOver labels remain attached to navigation, filters, controls, rows, and actions.
Reduce Motion behavior remains unchanged.
Arabic and mixed-language direction resolution remains covered by the existing RTL tests.
Compact layouts preserve full labels and avoid horizontal overflow.

## Proof locations

Phase 1 baselines are in `before/`.
Phase 1 corrected desktop captures are in `phase-1-after/`.
Phase 2 compact and maximized captures are in `phase-2-responsive/`.
The phase 2 folder also contains compact sort-menu and Opportunity Detail sheet proof.
