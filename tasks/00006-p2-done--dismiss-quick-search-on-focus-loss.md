# Dismiss Quick Search When Focus Moves Elsewhere

## Goal

Treat focus leaving the Quick Search panel as an implicit dismissal. When the user clicks another Paperclip window, another application, or another focusable system surface, Quick Search should disappear just as it does when Escape is pressed.

## Implementation

1. Add a panel focus-loss lifecycle hook in `QuickSearchManager.swift`, using the AppKit key-window resignation event (`NSWindowDelegate.windowDidResignKey` or an equivalently scoped panel notification).
2. Route that event through the existing `hideQuickSearch()` method so window visibility and `isQuickSearchVisible` remain synchronized in one place.
3. Keep the observer/delegate scoped to the reusable Quick Search panel and avoid reacting to unrelated Paperclip windows.
4. Preserve existing behavior: the global shortcut still opens/toggles Quick Search, each opening starts a fresh focused search session, Escape dismisses it, and selecting an item dismisses it.

## Verification

1. Add a focused UI regression covering: open Quick Search, move focus to another window/surface, and verify the Quick Search field disappears.
2. Run the existing Quick Search keyboard and restore tests to ensure typing, Escape, Enter, and Shift-Enter still behave correctly.
3. Build and run the relevant test targets.
4. Manually verify the intended cross-application journey if automated macOS UI isolation cannot reliably activate a second application in CI: open Quick Search, click a window from another app, and confirm immediate dismissal.

## Acceptance Criteria

- Quick Search closes when its panel loses key-window focus.
- Clicking a window from another app dismisses Quick Search without requiring Escape.
- Losing focus does not alter the clipboard or select/restore an item.
- Reopening Quick Search still shows an empty, focused query.
- Existing explicit dismissal and keyboard selection behavior remains unchanged.
