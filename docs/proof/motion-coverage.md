# Zoid 99 motion coverage

## Prior-work diagnosis

Zoid 99's `MOTION.md` entered the repository in the initial app commit `7f18a3e`.
No later Zoid 99 commit implemented a full motion pass, and no motion-specific branch or commit exists in repository history.
The installed build therefore did not lose or omit a later motion package.
It packaged the documentation-only baseline plus limited press scaling in `SumiButtonStyle` and `SumiPressStyle`.

Master Lance has no current or historical tracked file named `motion.md`.
Its real Sumi-Ink motion implementation is commit `f572b4a`, which changed `DESIGN.md`, React components, CSS, and end-to-end tests.
The useful language was route fade and lift, capped ledger sequencing, transform-and-opacity disclosure, active-only refresh feedback, written focus, one-point hover lift, and press feedback.
Web-only selectors, CSS keyframes, and page timings were not copied directly.

## Coverage matrix

| Surface | Motion coverage | Reduce Motion |
| --- | --- | --- |
| App shell and sidebar | Detail crossfade, selected ink transition, hover and press feedback | Near-instant opacity only |
| Today | Refresh label state, stable opportunity insertion and removal, row hover and press | No spatial list movement |
| Live Radar | Filter and sort controls, match-state fade, stable filtered and sorted collection | No spatial disclosure or reorder |
| Topics | Research state crossfade, evidence and related-opportunity identity changes | Opacity only |
| Comments | Stable comment-cluster collection changes | No spatial list movement |
| Watchlists | Filter state, validation error reveal, insertion, removal, priority state, sync status, sheets | Opacity only |
| Notifications | Permission state, delivery-state updates, stable ledger changes, row feedback | Opacity only |
| Sources and Settings | Toggles, steppers, provider state, source-health state, connection sheets, field feedback | No press scale, lift, or spatial reveal |
| Opportunity detail | Sheet presentation, disposition state, evidence identity changes, action feedback | Native presentation and opacity state |
| First run | Step crossfade and control feedback | Near-instant opacity only |
| Empty, loading, and error states | State replacement through shared opacity policy | Near-instant opacity only |
| Responsive window changes | Deliberately immediate to protect text sharpness, focus, and pointer targets | Same behavior |

## State and performance rules

Collections use model identifiers rather than indexes.
Rapid filtering and navigation retarget the current SwiftUI transition instead of launching detached animation work.
Stagger is capped at 180 milliseconds and is disabled for Reduce Motion.
Window geometry, field size, text layout, and large responsive reflow are not animated.
