# Make Quick Search a reliable keyboard-first workflow

## Goal

A user can invoke Quick Search while working in another macOS app, immediately type a query, navigate results, restore a clipboard item, and return to their work without touching the mouse.

## Current state

Quick Search has the core pieces but remains an unverified prototype:

- `KeyboardShortcuts` registers Cmd+Shift+Space globally.
- `QuickSearchManager` creates and reuses a floating `NSPanel`.
- `QuickSearchView` filters the shared clipboard history.
- `HistoryListView` handles arrows, Enter, and Shift+Enter.
- Enter copies and dismisses; Escape dismisses.
- No XCUITest exercises Quick Search.
- Focus depends on an unexplained 100 ms delay.
- Showing uses separate `orderFront` and `makeKey` calls.
- Hide animation can race with repeated show/hide input.
- Search text and selection behavior across repeated invocations are unspecified.
- The shortcut handler becomes active before the shared monitor is installed.

## User journey

1. sPaperclip is running in the background with clipboard history.
2. The user is active in another application.
3. The user presses Cmd+Shift+Space.
4. Quick Search appears above the active Space with its search field ready for the first keystroke.
5. Typing filters results and selects the first match.
6. Up/Down changes the selected result.
7. Enter restores every representation and dismisses Quick Search.
8. Shift+Enter restores plain text and dismisses Quick Search.
9. Escape dismisses without changing the pasteboard.
10. Invoking Quick Search again begins with an empty query and deterministic selection.

## Implementation plan

### 1. Make panel lifecycle deterministic

- Consolidate activation/show behavior around `makeKeyAndOrderFront`.
- Define one source of truth for visible/hiding state.
- Prevent hide-animation completion from hiding a panel that has already been shown again.
- Make repeated shortcut presses safe and deterministic.
- Keep the panel available across Spaces and fullscreen apps.
- Reset alpha and window state before every show.

### 2. Replace timer-based focus with session-based focus

- Remove the arbitrary `asyncAfter(0.1)` focus delay.
- Introduce an explicit Quick Search session/show signal.
- On every show, clear the prior query, reset result selection, and request search-field focus on the next valid UI lifecycle boundary.
- Verify the first typed character always lands in the search field.
- Cancel debounce subscriptions when no longer needed.

### 3. Fix initialization ordering

- Register the global shortcut only after the shared clipboard monitor is installed, or otherwise make monitor availability impossible to race.
- Ensure shortcut registration happens exactly once.

### 4. Add accessibility contracts

Add stable identifiers for:

- Quick Search panel/surface
- Search field
- Result list
- Result rows
- Empty/no-match state

Keep identifiers distinct from the main-window history so XCUITest can target the intended surface.

### 5. Add XCUITest journeys

Use the existing ad-hoc signed, isolated-store XCUITest setup.

Automate:

- Seed two distinct clipboard entries.
- Put another application in front and invoke Cmd+Shift+Space.
- Verify the panel appears and typing immediately reaches the search field.
- Filter, navigate with arrow keys, press Enter, verify the chosen pasteboard value, and verify dismissal.
- Invoke again and verify the query is reset.
- Press Escape and verify dismissal without pasteboard mutation.
- Cover Shift+Enter plain-text restore where a multi-format fixture is practical.

If macOS/XCUITest cannot reliably deliver the global chord from a second process, keep a deterministic menu-driven invocation test and document one manual global-shortcut acceptance check; do not add sleeps to hide test instability.

## Acceptance criteria

- Cmd+Shift+Space opens Quick Search while another app is active.
- Panel appears on the active Space and becomes key.
- Search field is focused for the first keystroke without a fixed time delay.
- Query filtering and first-result selection are deterministic.
- Up/Down navigation works while the search field remains the keyboard focus.
- Enter restores the selected item and dismisses the panel.
- Shift+Enter restores plain text and dismisses the panel.
- Escape dismisses without changing the pasteboard.
- Rapid toggle/show/hide input cannot leave an invisible key panel or stale visibility state.
- Every new invocation starts with an empty query and predictable selection.
- XCUITest covers invocation, typing, navigation, restoration, dismissal, and reinvocation.
- Existing unit tests and main-window XCUITests remain green.
- Debug and Release builds succeed.

## Non-goals

- Launch at login
- Favorites or pinned items
- Fuzzy/ranked search
- Multi-monitor positioning preferences
- Visual redesign beyond what is necessary for deterministic window behavior
- Replacing the clipboard polling architecture
