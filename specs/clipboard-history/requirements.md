# Clipboard History

## User Story

As a user, I need clipboard content captured faithfully and kept available so
that I can recover something I copied without returning to its source.

## Requirements

### REQ-CH-001: Capture Clipboard Changes Automatically

WHEN the system clipboard changes while Paperclip is running
THE SYSTEM SHALL add the new clipboard content to history within 1 second

**Rationale:** Clipboard history is useful only when capture is quiet and
automatic; users should not need a separate save action for every copy.

---

### REQ-CH-002: Preserve Every Available Representation

WHEN copied content is available in multiple representations
THE SYSTEM SHALL capture every available representation

WHEN a user restores a complete history item
THE SYSTEM SHALL write every captured representation back to the clipboard

IF no representation can be written during restoration
THE SYSTEM SHALL NOT report that the restoration succeeded

**Rationale:** Users expect restored content to paste with the same fidelity as
the original copy, including rich text, plain text, images, and other formats.

---

### REQ-CH-003: Keep One Copy Operation Together

WHEN multiple clipboard formats contain identical data
THE SYSTEM SHALL present them as one content group with multiple formats

WHEN one copy operation contains distinct data values
THE SYSTEM SHALL present those values as separate content groups within one
history item

**Rationale:** Users think of a copy operation as one item even when applications
place several related representations on the clipboard.

---

### REQ-CH-004: Find Recent Copies First

WHEN a user views clipboard history
THE SYSTEM SHALL display items in reverse chronological order

THE SYSTEM SHALL display when each item was captured

**Rationale:** Recent copies are usually the most useful, while timestamps help
users distinguish similar content.

---

### REQ-CH-005: Restore a Previous Copy

WHEN a user restores a history item
THE SYSTEM SHALL replace the clipboard contents with the selected item

WHEN restoration succeeds
THE SYSTEM SHALL identify the restored item as the current clipboard item

**Rationale:** Restoring a previous copy is the core value of maintaining
history, and the current marker prevents uncertainty about what will paste.

---

### REQ-CH-006: Keep History Bounded

WHEN history contains more than 100 items
THE SYSTEM SHALL remove the oldest items

THE SYSTEM SHALL retain the 100 most recent items

**Rationale:** A bounded history protects responsiveness and storage while
retaining enough recent material for everyday recovery.

---

### REQ-CH-007: Identify the Current Clipboard Item

WHEN a displayed history item matches the current clipboard contents
THE SYSTEM SHALL visually distinguish that item

WHEN no history item is known to match the current clipboard contents
THE SYSTEM SHALL NOT identify any item as current

**Rationale:** Users need an honest indication of what will paste, especially
after browsing or restoring an older item.

---

### REQ-CH-008: Retain Common and Unrecognized Content

WHEN the clipboard contains plain text, rich text, HTML, PNG, JPEG, TIFF, PDF,
URL, or file URL content
THE SYSTEM SHALL capture the available data

WHEN the clipboard contains an unrecognized format with readable data
THE SYSTEM SHALL capture the raw data and identify its format

**Rationale:** Clipboard use spans writing, development, design, and file
management. Retaining unrecognized data avoids silently discarding user data.
