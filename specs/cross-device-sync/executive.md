# Cross-Device Sync — Executive Summary

## Requirements Summary

Cross-Device Sync is an opt-in path for making text copied on a Mac available in
an iPhone companion app. The intended experience includes newest-first browsing,
full-text inspection, one-tap copy, offline access, consistent reconciliation,
and 7-day, 90-day, or permanent retention. Rich local clipboard history remains
on the Mac; only text enters the sync boundary.

## Technical Summary

The branch establishes an iOS target and a shared SwiftData `ClipboardItem`
model with text, timestamps, retention, and expiration fields. The iOS app uses
a disk-backed model container configured for automatic CloudKit integration and
provides list and detail views over locally available records. The production
macOS app continues to persist its rich multi-format history with Core Data and
does not yet create SwiftData sync records. Shared CloudKit entitlements,
explicit opt-in control, the macOS-to-sync projection, physical-device
verification, and retention editing remain incomplete. The storage boundary is
recorded in [ADR-000](../adrs/000_preserve-rich-local-history.md), and the
consent boundary in [ADR-001](../adrs/001_require-explicit-sync-opt-in.md).

## Status Summary

| Requirement | Status | Notes |
| --- | --- | --- |
| **REQ-CD-001:** Access History on an Opted-In Device | 🔄 In Progress | iOS SwiftData foundation exists; shared entitlements, macOS writes, explicit opt-in, and end-to-end sync are pending |
| **REQ-CD-002:** Browse Synced History on iPhone | 🔄 In Progress | Newest-first iOS list UI exists, but display of records synced from macOS is not yet verified |
| **REQ-CD-003:** Read a Synced Item in Full | ✅ Complete | iOS detail view presents selectable full text and retention metadata for available records |
| **REQ-CD-004:** Copy Synced Text on iPhone | 🟡 Functional with gaps | The Copy action writes text to the iOS clipboard but provides no success feedback |
| **REQ-CD-005:** Choose How Long Synced Text Is Kept | 🔄 In Progress | Shared policies and iOS badges exist; user-facing policy controls remain pending |
| **REQ-CD-006:** Hide Expired Synced Items | 🔄 In Progress | iOS filters expired local records; the complete cross-device retention flow is unverified |
| **REQ-CD-007:** Read Synced History Offline | 🔄 In Progress | iOS records are disk-backed; offline receipt and convergence still require device testing |
| **REQ-CD-008:** Converge Without Silent Data Loss | ❌ Not Started | No shared-container conflict, deletion, or retry behavior has been verified |
| **REQ-CD-009:** Preserve Mac History Across Relaunches | ✅ Complete | The production macOS history is stored and restored through Core Data |
| **REQ-CD-010:** Limit Cross-Device Data to Text | 🔄 In Progress | The shared model is text-only, but the Mac does not yet project captures into it |

**Progress:** 2 of 10 complete; 6 in progress; 1 functional with gaps; 1 not started

## Open Questions & Future Directions

- Physical-device acceptance must establish the observable conflict and retry
  behavior before `REQ-CD-008` can move out of not started.
- Binary synchronization remains outside the requirement set unless real usage
  demonstrates value worth the added privacy, storage, and fidelity costs.
