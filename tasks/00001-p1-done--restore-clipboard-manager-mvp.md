# Restore sPaperclip to a working, verified MVP

## Triage summary

The repository is clean and its current commit matches `main`/`origin/main` (`cfd7268`, 2025-05-16).

Current verdict: **the project has most of an MVP implemented, but the committed revision should not be expected to build or satisfy its advertised primary workflow.** It is a late prototype rather than a verified MVP.

Verified findings:

- A clean Xcode build fails because the app imports `KeyboardShortcuts`, while `spaperclip.xcodeproj` contains no Swift Package reference or linked package product. `Package.swift` declares the dependency, but the documented and primary Xcode build does not consume that manifest.
- In a scratch copy, removing/stubbing only the shortcut integration allows the rest of the app to build successfully with the current Xcode/SDK. This isolates the immediate compiler blocker rather than indicating broad source incompatibility.
- The latest pre-main commit itself describes Quick Search as “almost working” and the shortcut dependency as “borked.”
- The normal Enter action in `HistoryList` selects the item again instead of copying it, despite the README promising that Enter copies the selected result. Shift+Enter does copy plain text.
- `ContentView.onDisappear` stops clipboard monitoring, with no matching restart. Closing/hiding the main window can therefore disable the core background behavior while the app/menu bar item remains alive.
- The Clear History application command clears persistence directly but does not clear the monitor’s in-memory history, so the UI and database can disagree.
- Existing tests are predominantly duplicated text-chunking tests. The UI tests only launch the app and make no assertions. There are no tests for capture, copy-back, persistence, search selection, clearing, or shortcut behavior.
- Build metadata is inconsistent: Xcode targets macOS 15.1, README says macOS 15.0+, and `Package.swift` targets macOS 14. The project also lacks a committed package resolution for the Xcode build.

Not treated as verified blockers: macOS pasteboard polling does not inherently require a custom permission prompt, and the `KeyboardShortcuts` library is intended to register global shortcuts while an app is running. These should be validated at runtime rather than replaced speculatively.

## MVP definition

A working MVP must let a user:

1. Build and launch the macOS app from a clean checkout.
2. Copy text in another application and see it appear in sPaperclip history.
3. Search history from the main window and from Quick Search.
4. Invoke Quick Search with the configured global shortcut while another app is active.
5. Navigate results, press Enter to place the selected item on the pasteboard, and dismiss Quick Search.
6. Restore saved history after relaunch.
7. Clear history consistently from both memory and persistence.
8. Continue monitoring while the main window is closed but the application remains running.

Rich-format previews, statistics, launch-at-login, distribution/notarization, and advanced retention controls are useful follow-ups, not blockers for this recovery task.

## Implementation plan

### 1. Restore a reproducible build

- Add `KeyboardShortcuts` as an Xcode Swift Package dependency and link its product to the app target.
- Commit package resolution metadata and use one authoritative compatible version range/pin.
- Reconcile deployment-target documentation/configuration; keep the effective MVP requirement explicit and consistent.
- Confirm Debug and Release builds from a clean DerivedData directory.

### 2. Repair the core clipboard journey

- Route Enter through an actual copy-all operation rather than selection-only behavior.
- Ensure app-initiated copy-back updates the monitor’s pasteboard change tracking so selecting an old item does not create or reorder an unintended new capture.
- Dismiss Quick Search after successful Enter selection, matching the documented interaction.
- Keep Shift+Enter’s plain-text behavior coherent with normal Enter.
- Make Clear History use the monitor-level operation so published history, selection/current-item state, and persisted data clear together.
- Move monitoring ownership out of transient `ContentView.onDisappear`; monitoring should last for the application lifetime and stop only when appropriate.

### 3. Stabilize initialization and observable state

- Ensure the shared clipboard monitor is installed in Quick Search before shortcut-triggered display is possible, avoiding the startup no-op path.
- Remove redundant/manual publication where `@Published` already provides updates when safe to do so.
- Preserve the existing 100-item MVP limit, but verify that memory and persistence pruning remain consistent.
- Fix only lifecycle/timing issues demonstrated by tests or smoke testing; do not redesign polling or Core Data without evidence.

### 4. Add MVP-focused verification

Add focused automated coverage where platform APIs can be isolated reliably:

- filtering and selection behavior;
- copy-all and plain-text pasteboard writes/change tracking;
- clear-history in-memory state;
- duplicate/history ordering behavior;
- persistence save/load round trip using an isolated test store where practical.

Replace placeholder UI coverage with a minimal asserted launch smoke test. Avoid trying to make global OS shortcut delivery a brittle headless unit test; cover it in the manual acceptance matrix.

### 5. Update project documentation

- Replace overstated feature language with behavior actually verified by the acceptance checks.
- Document exact build/test commands, supported macOS version, default shortcut, retention limit, and known MVP limitations.
- Distinguish “app must be running” from optional future “launch at login” behavior.

## Acceptance checks

Run against a clean build on macOS:

- `xcodebuild` Debug build succeeds.
- `xcodebuild` Release build succeeds and produces `spaperclip.app`.
- Unit tests pass.
- App launches without an immediate Core Data failure.
- Copying unique text in another app adds one history item within the polling interval.
- Re-copying existing content does not create a duplicate record.
- Main-window search filters case-insensitively.
- With another app active, Cmd+Shift+Space opens Quick Search and focuses its field.
- Arrow navigation changes selection; Enter copies the selected full content and closes Quick Search; Escape closes without copying; Shift+Enter copies plain text.
- Closing the main window does not stop subsequent clipboard capture while sPaperclip remains running.
- Relaunch restores captured history.
- Clear History immediately empties the visible list and remains empty after relaunch.
- Text plus at least one representative image/URL item can be captured, previewed where supported, and copied back.

## Deliverable

A clean-checkout, buildable macOS app whose core capture → find → restore workflow is verified, plus honest setup/limitations documentation and regression coverage for the repaired MVP paths.
