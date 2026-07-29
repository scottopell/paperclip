# Polish daily-driving surfaces

## Goal

A user who closes every app window can reopen the full Clipboard History window from the persistent menu-bar popover without relaunching sPaperclip.

## Delivered

- Removed the main `WindowGroup` so SwiftUI scene destruction no longer controls the utility’s primary window.
- Added a native menu-bar menu with **Open Clipboard History**, **Quick Search**, **Database Statistics**, and **Quit sPaperclip**.
- **Open Clipboard History** activates sPaperclip and opens or focuses a full history window backed by the shared monitor.
- Replaced SwiftUI `WindowGroup` ownership with an app-lifetime `NSApplicationDelegate` and dedicated `NSWindowController`; closing hides rather than destroys the history window.
- Redesigned Quick Search as a wider two-pane surface: compact app/timestamp/result cards on the left and a full live preview of the selected item on the right.
- Preserved fuzzy search, current-item highlighting, automatic scrolling, arrow navigation, Enter/Shift+Enter, and Escape behavior.

XCUITest can discover the native status menu and its Open item after the last key window closes, but macOS automation times out dispatching that menu-item click. The lifecycle follows AppKit directly and remains a manual acceptance check rather than adding sleeps or a test-only invocation path.

## Acceptance criteria

- Closing the final Clipboard History window does not quit sPaperclip.
- The menu-bar status item remains available.
- Choosing **Open Clipboard History** from the menu-bar menu restores the full history UI and activates the app.
- Quick Search matches the compact-list/large-preview information architecture in the supplied mockup.
- Existing statistics and Quick Search behavior remain intact.
