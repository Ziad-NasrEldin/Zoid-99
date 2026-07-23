# Zoid 99 SUMI-E Motion System

Motion exists only to clarify state.
It must never compete with research content or slow repeated navigation.
These rules are adapted from the canonical design guidance and the established SwiftUI `SumiMotion` policy.

## Timing

- Button press: 150 milliseconds
- Hover state: approximately 180 milliseconds
- Dropdown disclosure: approximately 160 milliseconds
- Standard state change: 150 to 250 milliseconds
- Easing: ease out

## Behavior

- Button presses may scale to 0.97 or 0.98 when Reduce Motion is off.
- Hover feedback changes border, paper, ink, or seal state without lifting the surface.
- Dropdowns use opacity disclosure.
- Modal overlays use opacity only and remain centered.
- High-frequency sidebar navigation does not animate.
- Keyboard-initiated actions do not animate.
- Decorative entrances, bouncing, parallax, and novelty motion are prohibited.

## Reduced Motion

- Read the macOS Reduce Motion accessibility setting.
- Disable scale and spatial transitions when Reduce Motion is on.
- Preserve immediate selected, loading, success, error, and focus feedback.
- Never rely on motion to communicate a state change.

## Implementation policy

Use one shared SwiftUI motion policy.
The policy decides whether state animations, spatial transitions, and press scaling are permitted.
Screens must not invent separate motion timings.
