# Make Quick Search quiet, trustworthy, and paste automatically

## Goal

Paperclip launches without interrupting work, preserves the current clipboard when a restore is known to be invalid, and completes the Quick Search loop by pasting the selected history item into the application that was active before invocation.

## Delivered

- Removed automatic presentation of Clipboard History at launch; monitoring, the global shortcut, and the native status menu start quietly.
- Added prevalidation for full-format, single-content, and plain-text clipboard writes so known-invalid requests do not clear the existing pasteboard.
- Added an inline Quick Search error for restore failures and for automatic-paste limitations.
- Quick Search remembers the invoking external application, updates/promotes the selected clipboard item, checks Accessibility trust, hides, reactivates the target, and posts layout-aware Command-V events directly to that process.
- If Accessibility access is unavailable, Paperclip requests it, leaves the selected content on the clipboard, keeps Quick Search open, and states that automatic paste was not completed.
- Replaced deprecated AppKit activation APIs, marked statistics lifecycle main-actor-owned, cached timestamp formatting, and standardized the menu-bar icon/name.
- Added native status-menu access to Clipboard History, Quick Search, Settings, Database Statistics, and Quit.

## Evidence

- Unit tests preserve a sentinel pasteboard across an empty full-format restore and image-only plain-text restore.
- All 36 unit tests pass.
- Debug and Release builds succeed; the Release bundle passes strict deep signature verification.
- The focused Quick Search keyboard journey passes with quiet-launch setup, native-menu invocation, clipboard promotion, and Accessibility fallback.
- The quiet-launch journey passes: no history window appears until explicitly opened from the status menu.
- Automatic paste into a separate application remains a manual macOS-boundary acceptance check because it requires user-granted Accessibility permission and cross-process input delivery.

## Manual acceptance

1. Focus a text input in another application and type a marker.
2. Invoke Quick Search, select a text item, and press Enter.
3. Grant Accessibility access if prompted, then invoke and select again.
4. Verify the chosen content appears at the original insertion point and remains the active clipboard item.
5. Repeat with Shift+Enter on rich content and verify plain text is inserted.
6. Attempt Shift+Enter on an image-only item and verify the old clipboard remains intact and Quick Search explains the failure.
