# Clipboard History — Executive Summary

## Requirements Summary

Clipboard History quietly captures clipboard changes, preserves the available
representations, and keeps the latest 100 items available after relaunch. Users
can scan recent copies, identify the item that currently matches the clipboard,
and restore either a complete item or an explicit representation. Related
formats remain grouped as one copy operation so fidelity does not create visual
clutter.

## Technical Summary

`ClipboardMonitor` polls the macOS pasteboard every 500 milliseconds, groups
identical data representations, and owns the in-process browsing state.
`ClipboardPersistenceManager` maps captured items into a Core Data store managed
by `CoreDataManager`; history is loaded at startup and saved on background
contexts. Restore helpers write the requested representations before promoting
an item to the current position. The app keeps both memory and persistent
history bounded to 100 items. The separation between rich local history and the
text-only sync model is recorded in [ADR-000](../adrs/000_preserve-rich-local-history.md).

## Status Summary

| Requirement | Status | Notes |
| --- | --- | --- |
| **REQ-CH-001:** Capture Clipboard Changes Automatically | ✅ Complete | 500 ms pasteboard polling and immediate reconciliation before Quick Search opens |
| **REQ-CH-002:** Preserve Every Available Representation | ✅ Complete | Capture and all-representation restore paths are implemented; restore failure does not clear existing clipboard data |
| **REQ-CH-003:** Keep One Copy Operation Together | ✅ Complete | Equal data is grouped while distinct representations remain separate content groups |
| **REQ-CH-004:** Find Recent Copies First | ✅ Complete | History is ordered newest-first with relative and exact timestamps |
| **REQ-CH-005:** Restore a Previous Copy | ✅ Complete | Full-item, content-group, and single-format restore paths promote the restored item |
| **REQ-CH-006:** Keep History Bounded | ✅ Complete | In-memory and Core Data histories are capped at 100 items |
| **REQ-CH-007:** Identify the Current Clipboard Item | ✅ Complete | Current state is reconciled from the pasteboard and is left unset when it cannot be proven |
| **REQ-CH-008:** Retain Common and Unrecognized Content | ✅ Complete | Known formats and additional readable pasteboard types are retained |

**Progress:** 8 of 8 complete

## Open Questions & Future Directions

- The fixed 100-item limit may eventually need a storage-size dimension if
  real-world image histories make item count a poor proxy for resource use.
