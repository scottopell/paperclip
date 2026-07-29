# Improve Quick Search scanability and state clarity

## Goal

Reduce the cognitive work required to choose a clipboard result without adding latency or decorative motion to the Quick Search loop.

## Delivered

- Replaced dense absolute row timestamps with contextual recency such as **Just now**, **5 min ago**, **Yesterday**, or a recent weekday/date.
- Preserved the exact timestamp as hover help and in the existing exact formatter API.
- Introduced one reusable, non-color-only **Current** badge using `checkmark.circle.fill` plus text across Quick Search, full history, and detail preview.
- Made selection consistently own the accent treatment while Current remains an independent semantic state.
- Combined each Quick Search card into one VoiceOver element that announces selected/current state, recency, source application, content kind, and preview text.
- Added a restrained fixed footer documenting Return paste, Shift-Return plain-text paste, arrow navigation, and Escape dismissal.

## Evidence

- Pure tests cover relative recency and the combined result accessibility label.
- Exact timestamps remain available.
- All 39 unit tests pass; fuzzy-query median remains about 0.54 ms for 100 items.
- The focused Quick Search keyboard journey passes against the combined semantic rows.
- Debug and Release builds succeed.
- No animations, thumbnails, timers, or query-path work were added.
