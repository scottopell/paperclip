# Content Preview — Executive Summary

## Requirements Summary

Content Preview helps users scan, search, and inspect clipboard history without
slowing the keyboard-first restore loop. Rows show concise text and type cues;
the detail view supports text selection, image gestures, metadata, binary
fallbacks, and switching among distinct content groups. Search and keyboard
navigation provide the fastest path when the desired item is already known.

## Technical Summary

`HistoryListView` renders a lazy, searchable list and debounces full-history
search by 300 milliseconds. `ClipboardDetailView` selects among content groups,
delegating text to an AppKit text view and images to a PDFKit-backed view.
`LazyTextView` decodes away from the main thread and rejects stale or cancelled
results before updating the interface. Format-specific restore choices are
available from each row’s context menu. Unit and performance tests exercise
search ordering, text decoding, cancellation, pasteboard writes, and measured
large-text presentation.

## Status Summary

| Requirement | Status | Notes |
| --- | --- | --- |
| **REQ-CP-001:** Inspect Images with Native Gestures | ⚠️ Manual verification only | PDFKit supplies native zoom and pan; gesture smoothness still requires a trackpad acceptance check |
| **REQ-CP-002:** Inspect Large Text Without Freezing the App | ✅ Complete | Off-main decoding, stale-result rejection, cancellation, and measured 1 MB presentation coverage are in place |
| **REQ-CP-003:** Recognize Items at a Glance | ✅ Complete | Rows show bounded text previews, type indicators, source context, and timestamps |
| **REQ-CP-004:** Inspect Distinct Representations | ✅ Complete | Detail tabs switch content groups; row menus expose single-format and grouped restore actions |
| **REQ-CP-005:** Select Text from a Preview | ✅ Complete | The AppKit text view is selectable and supports native copy behavior |
| **REQ-CP-006:** Find History by Text | ✅ Complete | Search is case- and diacritic-insensitive, debounced, ordered, and covered for late matches in large text |
| **REQ-CP-007:** Navigate and Restore from the Keyboard | ✅ Complete | Arrow navigation, Return restore, and Shift-Return plain-text restore are implemented |
| **REQ-CP-008:** Understand Content Metadata | ✅ Complete | Detail view shows all format identifiers, byte size, and approximate text size |
| **REQ-CP-009:** Inspect Small Unrecognized Data | ✅ Complete | Binary byte count and bounded ASCII fallback are implemented |

**Progress:** 8 of 9 complete; 1 requires manual verification

## Open Questions & Future Directions

- Trackpad acceptance should establish whether the PDFKit preview remains smooth
  for the largest images users routinely copy.
