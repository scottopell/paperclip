# Cross-Device Sync

## User Story

As a user, I need the option to access selected clipboard history on my iPhone
so that I can reuse text from my Mac while preserving local-only clipboard
privacy by default.

## Requirements

### REQ-CD-001: Access History on an Opted-In Device

WHERE the user has explicitly enabled cross-device clipboard access
WHEN text content is captured on macOS
THE SYSTEM SHALL make the content available to the user's opted-in iOS devices

WHEN synchronization completes while the iOS app is open
THE SYSTEM SHALL show new items without requiring a manual refresh

IF the user has not enabled cross-device clipboard access
THE SYSTEM SHALL NOT transmit clipboard history

**Rationale:** Cross-device access is useful only when it remains a deliberate
choice for private clipboard data and does not require repeated refresh actions.

---

### REQ-CD-002: Browse Synced History on iPhone

WHEN a user opens the iOS companion app
THE SYSTEM SHALL display unexpired synced items in reverse chronological order

THE SYSTEM SHALL display a text preview and relative capture time for each item

**Rationale:** A concise, newest-first list lets users locate a recent Mac copy
quickly on a smaller screen.

---

### REQ-CD-003: Read a Synced Item in Full

WHEN a user opens a synced item
THE SYSTEM SHALL display its full text and allow text selection

THE SYSTEM SHALL display its capture time, retention policy, and expiration time
when one exists

**Rationale:** Full text and retention context let users inspect long content and
understand how long it remains available.

---

### REQ-CD-004: Copy Synced Text on iPhone

WHEN a user chooses Copy for a synced item
THE SYSTEM SHALL place the item's text on the iOS clipboard

WHEN the copy succeeds
THE SYSTEM SHALL provide visible or haptic confirmation

IF the item has no text that can be copied
THE SYSTEM SHALL NOT report success

**Rationale:** One explicit action should make a Mac copy ready to paste on the
iPhone, with honest feedback about whether it worked.

---

### REQ-CD-005: Choose How Long Synced Text Is Kept

WHEN a user chooses temporary retention
THE SYSTEM SHALL keep the item for 7 days from capture

WHEN a user chooses extended retention
THE SYSTEM SHALL keep the item for 90 days from capture

WHEN a user chooses permanent retention
THE SYSTEM SHALL keep the item without an expiration date

WHEN an item uses extended or permanent retention
THE SYSTEM SHALL distinguish that policy in the iOS history

**Rationale:** Routine copies should expire automatically while important text
can remain available for a user-chosen period.

---

### REQ-CD-006: Hide Expired Synced Items

WHEN a synced item's expiration time passes
THE SYSTEM SHALL exclude the item from displayed history

**Rationale:** Expired content should leave the working set without requiring
manual cleanup.

---

### REQ-CD-007: Read Synced History Offline

WHEN an iOS device has no network connection
THE SYSTEM SHALL display unexpired items already available on that device

WHEN connectivity returns
THE SYSTEM SHALL reconcile changes made while a device was offline

**Rationale:** Locally available clipboard history remains useful on a plane,
subway, or unreliable connection.

---

### REQ-CD-008: Converge Without Silent Data Loss

WHEN the same synced item changes independently on multiple devices
THE SYSTEM SHALL converge to one value and display that value consistently

WHEN a synced item is deleted on one device
THE SYSTEM SHALL propagate the deletion to other opted-in devices

IF synchronization encounters a temporary error
THE SYSTEM SHALL retry without falsely reporting that the unsynchronized change is
available everywhere

**Rationale:** Users need one understandable history across devices and must not
be misled when a change has not reached another device.

---

### REQ-CD-009: Preserve Mac History Across Relaunches

WHEN macOS captures a clipboard item
THE SYSTEM SHALL persist the item locally

WHEN the macOS app relaunches
THE SYSTEM SHALL restore the retained local history

**Rationale:** Clipboard history must survive the application lifecycle whether
or not cross-device access is enabled.

---

### REQ-CD-010: Limit Cross-Device Data to Text

WHERE cross-device clipboard access is enabled
THE SYSTEM SHALL synchronize text representations

THE SYSTEM SHALL NOT synchronize images, PDFs, files, or other binary
representations

WHEN an item contains no text representation
THE SYSTEM SHALL keep the item local to the Mac

**Rationale:** Text provides the common cross-device workflow without exposing
large or sensitive binary clipboard data to cloud storage. See
[ADR-000](../adrs/000_preserve-rich-local-history.md).
