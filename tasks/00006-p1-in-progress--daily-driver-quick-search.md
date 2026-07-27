# Make Quick Search the daily-driver clipboard path

## Goal

Quick Search should make the common clipboard workflow effortless: invoke it from any app, start on the actual current clipboard item, fuzzily find an older entry, navigate entirely from the keyboard, and press Enter to make the chosen entry the current/top clipboard item.

## Current behavior and gaps

The repository already has a strong keyboard-first base:

- Control+Option+Space opens a reusable floating panel.
- Each presentation clears and focuses the query field.
- Empty-query results preserve newest-first history order and select the first row.
- Up/Down navigation, Enter copy-all, Shift+Enter plain-text copy, Escape, dismissal, and reinvocation are covered by XCUITest.
- Quick Search filtering is immediate and measured well below its 50 ms budget for 100 items.

The remaining gaps against the desired happy path are:

- Search is only `localizedCaseInsensitiveContains`; it is not fuzzy and does not rank matches.
- Initial selection assumes `history.first` is the current pasteboard item rather than selecting `currentItemID` explicitly. The 500 ms polling interval can also leave history stale if Quick Search opens immediately after an external copy.
- Restoring a history item writes it to `NSPasteboard`, but intentionally suppresses recapture. Consequently, the restored row is not promoted in history, `currentItem`/`currentItemID` remain stale, and the promoted recency is not retained across relaunch.
- Existing tests verify substring filtering and pasteboard output, but not fuzzy ranking, current-item selection, or promotion semantics.

## Required behavior

### Session startup

- When Quick Search opens, reconcile any pending external pasteboard change before establishing results and selection.
- With an empty query, select the history row represented by `currentItemID` when present.
- Fall back deterministically to the first/newest row when no current ID is available; remain unselected for empty history.
- Preserve immediate first-keystroke focus and the existing fresh-query behavior on every invocation.

### Fuzzy search

- Match case- and diacritic-insensitively against textual clipboard history.
- Support ordered, non-contiguous character matching so abbreviated input can find a longer value.
- Rank stronger matches first, with an explicit deterministic scoring policy that favors, in order: exact/contiguous matches, word or token starts, tighter character spans, and fewer gaps.
- Use current history order (recency) as the final tie-breaker.
- Preserve history order for an empty query.
- Select the top-ranked result whenever the query changes; clear selection for no matches.
- Keep query processing comfortably below the existing 50 ms median gate for the 100-item history limit.
- Implement this locally unless measurement demonstrates a need for another dependency.

### Restore and promotion

- Enter must copy every captured representation; Shift+Enter must retain plain-text-only behavior.
- After a successful pasteboard write, atomically make the selected entry the first history row and update `currentItem`, `currentItemID`, and selection to that entry.
- Persist the recency change so the same entry remains first after relaunch without creating a duplicate persisted item.
- A failed pasteboard write must not reorder history or dismiss Quick Search.
- A successful write dismisses Quick Search as it does today, and the app must not later recapture its own write as a duplicate.

## Implementation plan

1. Extract a pure fuzzy matcher/ranker used by `QuickSearchQuery`, returning a deterministic ordered result snapshot while keeping the main-window search behavior unchanged unless explicitly shared without regressions.
2. Add a monitor operation that reconciles a pending pasteboard change for Quick Search startup without waiting for the polling timer.
3. Initialize the Quick Search result snapshot and selection from the reconciled `currentItemID`, with clear fallback rules.
4. Centralize successful restore bookkeeping in `ClipboardMonitor`: pasteboard change tracking, in-memory promotion/current state, and persistence recency update should be one coherent operation used by Enter and Shift+Enter.
5. Add persistence support to promote an existing semantic history record rather than inserting another record.
6. Extend unit, performance, and UI journey coverage; update README Quick Search language to describe fuzzy matching and promotion.

## Verification

### Unit tests

Cover:

- empty query preserves input order;
- exact, prefix/word-start, contiguous substring, and gapped fuzzy matches rank predictably;
- matching is case- and diacritic-insensitive;
- non-matches are excluded and recency breaks equal-score ties;
- current-ID selection wins even if it is not accidentally the first array element;
- successful copy-all and plain-text restore promote and update all current/selection state;
- failed restore leaves state and ordering unchanged;
- promotion does not create a duplicate persisted record and survives reload.

### Performance test

Retain one warmup and at least five raw samples over 100 realistic entries. Assert identical deterministic IDs across runs and a median query-to-results latency below 50 ms.

### XCUITest journey

- Capture multiple values and open Quick Search immediately after the newest copy.
- Verify the current clipboard row is selected initially.
- Type an abbreviation that only fuzzy matching can resolve.
- Navigate with Up/Down and press Enter.
- Verify the selected value is on `NSPasteboard`, the panel dismisses, and reopening starts with that value as the current/top selected row.
- Retain Escape, fresh-query, and Shift+Enter coverage.

Run the full unit suite, focused Quick Search UI tests, and Debug/Release builds.

## Acceptance criteria

- The global shortcut opens a focused Quick Search session from another app.
- The actual current clipboard item is selected on open, including when invoked before the next polling tick.
- Fuzzy abbreviations find and sensibly rank clipboard text while exact matches remain strongest.
- Up/Down never loses search-field focus and remains clamped to available results.
- Enter/Shift+Enter make the chosen value current, promote it to the first history row, persist that order, and dismiss only after success.
- Reopening starts empty and selects the newly promoted current item.
- No self-copy duplicate is captured.
- Quick Search remains below the 50 ms median query latency gate at the 100-item limit.
- Existing main-window clipboard workflows and tests remain green.

## Non-goals

- Visual redesign of the panel
- Increasing the 100-item history limit
- Replacing pasteboard polling or Core Data
- Automatic paste into the previously focused application
- Favorites, pinning, OCR, or searching non-text binary payloads
