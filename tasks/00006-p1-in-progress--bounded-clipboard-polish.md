# Deliver a bounded clipboard polish bundle

## Goal

Make the app’s core capture, search, restore, and clear-history journeys feel trustworthy without redesigning the application or replacing its clipboard-monitoring architecture.

## User-visible scope

### 1. Make the “Current” marker truthful

Treat the green current-clipboard marker as a claim about content the app has actually observed or restored:

- Do not mark the first persisted history item as current merely because it is newest at launch; leave the marker unset until the current process observes a clipboard change or restores an item.
- When a newly observed clipboard value matches an existing history item, point `currentItem`, `currentItemID`, and selection at that existing item rather than at the temporary duplicate model.
- After any successful full-content, single-content, or plain-text restore, update current-item state to the restored history item when one is available.
- Do not change current-item state when a pasteboard write fails.

This task does not change the existing duplicate-history policy or attempt to reconcile the launch-time system pasteboard against persisted history.

### 2. Make format-specific copy honest

- Add a copy operation that writes one selected `ClipboardFormat` only.
- Wire each format submenu action to that operation instead of copying every format in its content group.
- Keep content-group copy and “Copy All Content Types” as separate, explicitly labelled actions.
- Preserve the app’s own-write suppression and current-item bookkeeping for every successful copy path.

### 3. Search complete large plain-text entries

The main window and Quick Search must find a query anywhere in a decodable plain-text clipboard entry, not only in its first 1,000 characters.

Implementation constraints:

- Separate concise preview generation from search extraction; previews must remain bounded and cheap.
- Add a lazily populated, memory-bounded search-text cache keyed to the lifetime of clipboard content, so repeated keystrokes do not repeatedly decode the same large value.
- Give the cache an explicit total-cost limit and allow eviction; do not add a persistent index, schema migration, or duplicate copy of every history item at startup.
- Preserve `localizedCaseInsensitiveContains` matching and history order.
- Search all text-capable representations using their existing decoders where safe. At minimum, complete UTF-8/UTF-16/ASCII plain text and URL text must work. Existing safety limits for oversized rich text or HTML may remain and must be documented in code/tests.
- Keep filtering synchronous at the existing call sites for this bounded change; use caching and the 100-item history cap to control cost rather than introducing an asynchronous search state machine.
- Keep main-window debounce and Quick Search’s immediate, single-pass result snapshot behavior.

### 4. Protect destructive clearing

- Route the Clipboard menu’s Shift-Command-K action through a confirmation dialog before deleting history.
- Reuse one confirmation message and destructive action contract for menu- and statistics-initiated clearing where practical.
- Cancel must leave in-memory and persisted history untouched.
- Remove the statistics view’s fixed 500 ms refresh assumption: add completion/event-driven clearing so displayed statistics refresh only after the persistence operation completes.
- Disable or no-op clear actions when history is already empty.

### 5. Add lightweight copy feedback and accessibility semantics

- After the detail-pane copy button succeeds, expose a compact “Copied” state (for example, a checkmark and text) until selection changes or another action supersedes it; expose a failure state if no representation could be written. Do not add timer-based toast coordination.
- Give icon-only controls explicit accessibility labels.
- Give history rows a useful combined accessibility label, selected-state trait/value, and button/selectable semantics while preserving existing mouse and arrow-key behavior.
- Give current/type indicators meaningful accessibility labels instead of relying only on color or hover help.
- Preserve stable accessibility identifiers used by existing UI tests.

## Implementation sequence

1. Extract pasteboard write helpers for one format, one content group, and a whole item; return enough information for the monitor to update state only on success.
2. Centralize current-item bookkeeping in `ClipboardMonitor`, then cover observed-new, observed-duplicate, restore-success, restore-failure, and launch-with-persisted-history behavior.
3. Split preview text from full searchable text and introduce the bounded cache; route `ClipboardHistoryFilter` through the searchable representation.
4. Introduce completion-aware persistence clearing and a shared confirmation path; remove the delayed stats refresh.
5. Add copy-result state and row/control accessibility metadata without changing the overall split-view layout.
6. Add focused unit and UI regression coverage, then run build, unit, performance, and selected UI journeys.

## Tests and evidence

### Unit tests

- A large plain-text item with the only matching phrase beyond character 100,000 is returned by `ClipboardHistoryFilter`.
- Large-text matching remains case-insensitive and preserves history order.
- UTF-16 large text and a multi-byte UTF-8 query match correctly beyond the old preview boundary.
- Repeated queries reuse cached decoded text; cache eviction does not change results.
- Preview generation remains bounded and does not expose the full large value.
- Selecting one format writes only that pasteboard type; content-group and whole-item copy retain all intended types.
- Failed writes do not update current-item state.
- Duplicate observation and successful restore produce a `currentItemID` that belongs to the displayed history.
- Loading persisted history alone leaves current-item state unset.
- Clear completion is delivered after the Core Data operation finishes.

### Performance gates

Extend the existing raw-sample Quick Search performance test with a realistic bounded worst case:

- 100 history items containing 1 MiB plain-text values, with a late match in a subset of entries.
- Warm the lazy cache once, then record five raw query samples.
- Preserve ordered result IDs.
- Warm-cache median query latency must remain below 50 ms.
- Report the one-time cold-cache sample separately for visibility; do not average it into the warm-cache gate.
- Retain the existing 100-small-item Quick Search gate.

### UI journeys

- Restoring an older row updates the visible Current marker and presents copy success feedback.
- Cancelling the menu Clear History confirmation preserves the list; confirming empties it.
- Existing capture/search/restore and Quick Search keyboard journeys remain green.
- Where reliable in XCUITest, assert row accessibility selection/current semantics; otherwise cover their generated labels/traits with focused view or accessibility inspection tests.

## Acceptance criteria

- Searching either surface finds complete large plain-text content beyond the old 1,000-character preview.
- Repeated large-text queries meet the warm-cache performance gate without unbounded retained search strings.
- Format-labelled menu actions place only the selected format on the pasteboard.
- The Current marker is never assigned to a temporary item absent from displayed history and is not guessed from persistence at launch.
- Successful restores visibly and accessibly confirm success; failures are not reported as success.
- Every user-facing clear-history action requires confirmation and statistics refresh after actual completion, not after a delay.
- History rows and icon-only actions expose meaningful accessibility labels and selection/current state.
- Debug and Release builds succeed.
- Unit tests, performance gates, and the focused UI journeys pass.

## Explicit non-goals

- Fuzzy, ranked, tokenized, or metadata search
- A persistent full-text index or Core Data migration
- Searching arbitrary binary formats
- Removing the 100-item history cap
- Changing duplicate entries into separately timestamped events
- Launch-time reconciliation of the system pasteboard with persisted history
- Replacing polling with pasteboard notifications
- Native `List` migration or broad visual redesign
- PDF/image preview redesign
- Toast infrastructure or timer-driven transient notifications
- Launch at login, favorites, pinning, retention preferences, or configurable history limits
