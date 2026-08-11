# Content Preview

## User Story

As a user, I need to scan and inspect clipboard content with familiar macOS
interactions so that I can choose the right item without interrupting my work.

## Requirements

### REQ-CP-001: Inspect Images with Native Gestures

WHEN a user previews an image
THE SYSTEM SHALL support pinch-to-zoom and two-finger panning

WHILE a user zooms or pans an image
THE SYSTEM SHALL keep the preview responsive to further input

**Rationale:** Familiar trackpad gestures make image inspection immediate and
keep Paperclip consistent with other Mac applications.

---

### REQ-CP-002: Inspect Large Text Without Freezing the App

WHEN a user previews text content larger than 100 KB
THE SYSTEM SHALL begin displaying content within 1 second

WHILE large text is loading
THE SYSTEM SHALL keep the rest of the interface responsive

WHEN a user leaves the large-text preview before loading completes
THE SYSTEM SHALL cancel the unfinished presentation

**Rationale:** Logs, code, and data exports can be large; inspecting one should
not block search, selection, or dismissal.

---

### REQ-CP-003: Recognize Items at a Glance

WHEN a history item contains text
THE SYSTEM SHALL display a preview of its first approximately 100 characters

WHEN a history item contains text, image, or URL representations
THE SYSTEM SHALL display indicators for the represented content types

THE SYSTEM SHALL display when each history item was captured

**Rationale:** Compact previews and type cues let users scan history without
opening each item.

---

### REQ-CP-004: Inspect Distinct Representations

WHEN a history item contains multiple content groups
THE SYSTEM SHALL allow the user to switch between the groups

WHEN a content group contains multiple format representations
THE SYSTEM SHALL allow the user to inspect and explicitly copy a chosen format

**Rationale:** A single copy can contain meaningfully different text, image, or
format representations, and users need explicit control over which one they use.

---

### REQ-CP-005: Select Text from a Preview

WHEN a user views text content
THE SYSTEM SHALL allow selection of a portion of the text

WHEN text is selected
THE SYSTEM SHALL support the standard macOS Copy command

**Rationale:** Users often need only part of a prior copy, and standard text
selection avoids forcing an all-or-nothing restore.

---

### REQ-CP-006: Find History by Text

WHEN a user enters a search query
THE SYSTEM SHALL show only history items containing that text without regard to
case or diacritics

WHEN the query changes
THE SYSTEM SHALL update the results within 500 milliseconds

WHEN no history item matches the query
THE SYSTEM SHALL display a no-results message

**Rationale:** Text search makes a bounded history useful when the desired item
is not among the most recent copies.

---

### REQ-CP-007: Navigate and Restore from the Keyboard

WHEN the history list has keyboard focus
THE SYSTEM SHALL use the Up and Down Arrow keys to move selection

WHEN a user presses Return on a selected item
THE SYSTEM SHALL restore every captured representation

WHEN a user presses Shift-Return on a selected item containing plain text
THE SYSTEM SHALL restore only the plain-text representation

**Rationale:** Keyboard navigation protects the invoke, choose, and return loop
from unnecessary pointer interaction.

---

### REQ-CP-008: Understand Content Metadata

WHEN a user views content details
THE SYSTEM SHALL display its format identifiers and byte size

WHEN the content can be interpreted as text
THE SYSTEM SHALL display an approximate character count

**Rationale:** Format and size information helps users diagnose why content may
paste or render differently between applications.

---

### REQ-CP-009: Inspect Small Unrecognized Data

WHEN content cannot be rendered as text or an image
THE SYSTEM SHALL display its byte size

WHEN unrecognized content is smaller than 1 KB
THE SYSTEM SHALL display printable ASCII characters and represent non-printable
bytes with placeholders

**Rationale:** A bounded fallback preview is more informative than silently
discarding or labeling user data as unsupported.
