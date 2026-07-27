# Zoid 99 SUMI-E Motion System

Motion exists only to clarify hierarchy, causality, feedback, or a state change.
It must never compete with research content, delay keyboard work, or make live data unstable.
The language is adapted from Master Lance's Sumi-Ink interaction work at commit `f572b4a`, then translated from web CSS into native SwiftUI behavior.

## Character

- Ink spreading becomes a short opacity transition.
- A brush settling becomes a one-point hover lift and a subtle press scale.
- Paper reveal becomes a seven-point disclosure offset paired with opacity.
- Calm momentum becomes an exponential ease-out curve without bounce or overshoot.

## Tokens

| Purpose | Duration |
| --- | --- |
| Press feedback | 100 milliseconds |
| Hover feedback | 140 milliseconds |
| Dropdown and popover disclosure | 180 milliseconds |
| Standard state change | 200 milliseconds |
| Page crossfade | 220 milliseconds |
| Exit | 140 milliseconds |
| Reduced Motion opacity change | 80 milliseconds |

The shared curve is `0.16, 1, 0.3, 1`.
Stagger is 30 milliseconds per item and is capped at 180 milliseconds.
Screens must not invent separate timings.

## Behavior

- Pointer navigation crossfades the detail surface without moving the large layout.
- Sidebar selection changes ink, paper, and seal state.
- Buttons and links use a one-point hover lift and scale to `0.98` while pressed.
- Fields change their rule from ink to seal on pointer hover without moving text or changing layout.
- Dropdowns reveal with opacity and a seven-point paper offset.
- Checkbox marks and written states crossfade.
- Stable collections animate insertions, removals, and reordering by identity.
- Sheets remain centered and rely on native presentation plus internal opacity state changes.
- Loading and source-health motion exists only while real state changes occur.
- Window resizing and major responsive reflow never animate because doing so can blur text, delay input, and destabilize focus.
- Keyboard navigation is not wrapped in explicit spatial animation.

## Reduced Motion

- Read the macOS Reduce Motion accessibility setting through SwiftUI.
- Disable press scaling, hover lift, spatial disclosure, and stagger.
- Preserve an 80-millisecond opacity transition for state continuity.
- Keep written loading, selected, success, error, focus, and source-health labels.
- Never rely on motion alone to communicate meaning.

## Performance and state safety

- Animate transforms and opacity instead of width, height, padding, or window geometry.
- Key list motion to stable model identifiers.
- Let SwiftUI retarget an interrupted state animation instead of starting detached animation tasks.
- Cap stagger so large live-data lists remain immediately usable.
- Keep focus, keyboard shortcuts, VoiceOver labels, and Arabic text direction independent from animation.
