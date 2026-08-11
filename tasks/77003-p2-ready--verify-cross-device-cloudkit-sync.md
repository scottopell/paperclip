Phase 7 of the cross-device clipboard-sync rollout. Depends on macOS SwiftData persistence and the shared CloudKit container.

Scope:
- .github/workflows/ci.yml: build both application schemes so target drift is caught automatically.
- MIGRATION_PLAN.md: record the physical-device acceptance matrix and verified results.
- tasks/: capture any concrete defects found during the device test as separate tasks.

Acceptance:
- A text item copied on the Mac appears on a physical iPhone signed into the same iCloud account.
- The iOS detail view shows the full text and its Copy action places the value on the iOS clipboard.
- Changes made while one device is offline converge after reconnecting.
- Both schemes pass CI builds.

Out of scope: retention-policy editing and iOS keyboard/share extensions.
