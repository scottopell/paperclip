# ADR-000: Preserve Rich Local History Beside the Text Sync Projection

- **Status:** Accepted
- **Date:** 2026-08-10 (formalized from existing design)
- **Affects:** REQ-CH-002, REQ-CH-003, REQ-CH-008, REQ-CD-001, REQ-CD-009, REQ-CD-010

## Context

Paperclip's macOS history captures arbitrary pasteboard representations and
restores them together. Its Core Data graph persists that rich content across
relaunches. The iOS companion needs a smaller record that SwiftData can store
locally and synchronize through CloudKit. Replacing the local graph risks
degrading clipboard fidelity and the Quick Search path; synchronizing the full
graph sends binary clipboard data to the network and increases schema, storage,
and migration complexity.

## Options considered

1. **Replace local history with the shared SwiftData model.** This gives both
   targets one store and one model, but the text-oriented record cannot preserve
   the Mac's multi-format clipboard contract without a much larger migration.
2. **Synchronize the complete rich clipboard graph.** This maximizes parity
   between devices, but uploads images and arbitrary binary data, increases
   CloudKit cost and failure surface, and puts sync concerns on the core local
   clipboard path.
3. **Keep rich Core Data history local and project text into a separate shared
   model.** The Mac preserves its current fidelity and performance boundaries;
   opted-in cross-device access receives only the smaller text record it needs.

## Decision

Adopt option 3. Core Data remains the canonical store for rich macOS clipboard
history. Cross-device sync uses a separate SwiftData projection containing text
and sync-specific metadata. A failed or unavailable sync projection must not
prevent local capture, browsing, or restoration.

## Consequences

- **Positive:** The local clipboard contract and Quick Search path stay
  independent of CloudKit availability, and binary clipboard data remains local.
- **Negative:** The Mac must map between two models and define duplicate,
  deletion, and retention behavior across their boundary.
- **Neutral:** The iOS companion intentionally exposes a narrower history than
  the Mac and cannot restore representations absent from the text projection.

## References

- [`../clipboard-history/requirements.md`](../clipboard-history/requirements.md)
- [`../cross-device-sync/requirements.md`](../cross-device-sync/requirements.md)
- `CoreDataManager`, `ClipboardPersistenceManager`, and `ClipboardItem`
- [`../../MIGRATION_PLAN.md`](../../MIGRATION_PLAN.md)
