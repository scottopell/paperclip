# Migration Plan: Add iOS App + iCloud Sync to spaperclip

## Overview

**Goal:** Add an iOS companion app that syncs clipboard history from macOS via iCloud.

**Architecture:**
- One Xcode project with two targets (macOS app, iOS app)
- Shared SwiftData model in `Shared/` folder
- iCloud sync via SwiftData's built-in CloudKit support

**Glossary:**
- **Target** = One thing Xcode builds (an app). One project can have multiple targets.
- **SwiftData** = Apple's modern persistence framework. Handles local storage + iCloud sync.
- **CloudKit Container** = Your app's private cloud database. Both apps use the same one.

---

## Phase 1: Create Shared Data Model

> Claude can do these steps.

- [x] **1.1** Create `Shared/` directory
- [x] **1.2** Create `Shared/ClipboardItem.swift` with SwiftData `@Model`
- [x] **1.3** Create `Shared/RetentionPolicy.swift` for the retention enum

---

## Phase 2: Create iOS App Directory Structure

> Claude can do these steps.

- [x] **2.1** Create `ClipboardViewer-iOS/` directory
- [x] **2.2** Create `ClipboardViewer-iOS/ClipboardViewerApp.swift` (iOS app entry point)
- [x] **2.3** Create `ClipboardViewer-iOS/ContentView.swift` (iOS main view)
- [x] **2.4** Create `ClipboardViewer-iOS/Assets.xcassets/` placeholder
- [x] **2.5** Create `ClipboardViewer-iOS/Info.plist` (can be minimal, Xcode fills in defaults)

---

## Phase 3: Add iOS Target in Xcode

> You must do these steps in Xcode. Claude cannot modify .xcodeproj reliably.

- [x] **3.1** Open `spaperclip.xcodeproj` in Xcode
- [x] **3.2** File menu → New → Target...
- [x] **3.3** Select "iOS" tab at top, then "App", click Next
- [x] **3.4** Configure the new target:
  - **Product Name:** `ClipboardViewer`
  - **Team:** Your Apple Developer team
  - **Organization Identifier:** `com.scottopell` (or your preference)
  - **Interface:** SwiftUI
  - **Language:** Swift
  - **Storage:** None (we'll add SwiftData manually)
  - Click Finish
- [x] **3.5** Xcode creates a `ClipboardViewer/` folder — you can delete it (we'll use our `ClipboardViewer-iOS/` instead)
- [x] **3.6** Delete the auto-generated `ClipboardViewer/` folder from the project navigator (Move to Trash)

---

## Phase 4: Add Existing Files to Targets

> You must do these steps in Xcode.

- [x] **4.1** Drag the `Shared/` folder into the Xcode project navigator (left sidebar)
  - When prompted: check "Copy items if needed" = NO (files are already in repo)
  - Add to targets: check BOTH `spaperclip` AND `ClipboardViewer`
  - Click Finish
- [x] **4.2** Drag the `ClipboardViewer-iOS/` folder into the project navigator
  - Add to targets: check only `ClipboardViewer`
  - Click Finish
- [x] **4.3** ~~Info.plist configuration~~ (Skipped - modern Xcode auto-generates this)
- [x] **4.4** Verify: Select `ClipboardItem.swift`, check File Inspector (right sidebar)
  - Under "Target Membership", both `spaperclip` and `ClipboardViewer` should be checked

**Build Status:** Both targets build successfully (verified via xcodebuild)

---

## Phase 5: Configure iCloud + CloudKit

> You must do these steps in Xcode. This enables sync.

### 5A: Configure macOS app (spaperclip)

- [ ] **5.1** Select the project in navigator → select `spaperclip` target
- [ ] **5.2** Go to "Signing & Capabilities" tab
- [ ] **5.3** Click "+ Capability" → search "iCloud" → add it
- [ ] **5.4** In the iCloud capability section:
  - Check "CloudKit"
  - Under Containers, click "+" and create: `iCloud.com.scottopell.spaperclip`
  - (Or use an existing container if you have one)
- [ ] **5.5** Xcode will create/update `spaperclip.entitlements` automatically

### 5B: Configure iOS app (ClipboardViewer)

- [ ] **5.6** Select `ClipboardViewer` target
- [ ] **5.7** Go to "Signing & Capabilities" tab
- [ ] **5.8** Click "+ Capability" → add "iCloud"
- [ ] **5.9** In the iCloud capability section:
  - Check "CloudKit"
  - Select the SAME container: `iCloud.com.scottopell.spaperclip`
- [ ] **5.10** Xcode will create `ClipboardViewer.entitlements` automatically

**Important:** Both apps MUST use the same CloudKit container identifier for sync to work.

---

## Phase 6: Update macOS App to Use SwiftData

> Claude can write the code. You wire it up in Xcode.

- [ ] **6.1** Create `Shared/ModelContainerSetup.swift` with shared container configuration
- [ ] **6.2** Update `spaperclip/spaperclipApp.swift` to use `.modelContainer()`
- [ ] **6.3** Update `ClipboardMonitor.swift` to save `ClipboardItem` objects to SwiftData
- [ ] **6.4** Update macOS views to query SwiftData instead of in-memory array

---

## Phase 7: Build and Test

> You must do these steps.

- [ ] **7.1** Select `spaperclip` scheme, build (Cmd+B) — fix any errors
- [ ] **7.2** Select `ClipboardViewer` scheme, build — fix any errors
- [ ] **7.3** Run macOS app, copy some text, verify it appears in the UI
- [ ] **7.4** Run iOS app in simulator, verify synced items appear (may take a few seconds)
- [ ] **7.5** Test on real devices (simulator CloudKit sync can be flaky)

---

## Phase 8: Add Retention Policy UI

> Claude can write the code. This is the "save forever" / "90 days" feature.

- [ ] **8.1** Add retention policy picker to macOS detail view
- [ ] **8.2** Add retention policy display to iOS view
- [ ] **8.3** Implement expiration filtering (hide expired items)

---

## File Structure When Complete

```
spaperclip/
├── spaperclip.xcodeproj
├── MIGRATION_PLAN.md              ← You are here
├── Shared/                        ← Used by both targets
│   ├── ClipboardItem.swift        ← SwiftData model
│   ├── RetentionPolicy.swift      ← Enum for 7d/90d/forever
│   └── ModelContainerSetup.swift  ← Shared SwiftData config
├── spaperclip/                    ← macOS app
│   ├── spaperclipApp.swift        ← Updated to use SwiftData
│   ├── ClipboardMonitor.swift     ← Updated to persist items
│   ├── ContentView.swift
│   └── ...
├── ClipboardViewer-iOS/           ← iOS app
│   ├── ClipboardViewerApp.swift
│   ├── ContentView.swift
│   ├── Info.plist
│   └── Assets.xcassets/
└── spaperclipTests/
    └── ...
```

---

## Future: iOS Extensions (from SnippetManager)

> These features are inspired by ~/dev/mono/SnippetManager. To be designed before implementation.

### Custom Keyboard Extension

**What it does:** A custom iOS keyboard that lets you insert saved clipboard items/snippets while typing in any app.

**User flow:**
1. User is typing in any app (Messages, Mail, Notes, etc.)
2. User switches to the ClipboardViewer keyboard
3. Keyboard shows list of saved snippets/clipboard items
4. User taps an item → text is inserted at cursor position

**Key considerations:**
- Keyboard extensions have strict memory limits (~50MB)
- Height is constrained (~100pt)
- Needs to access shared SwiftData store via App Groups
- Privacy: Should NOT request "Allow Full Access" (keeps data local)

### Share Extension

**What it does:** Save text from any app to your clipboard history via the iOS share sheet.

**User flow:**
1. User selects text in Safari, Notes, etc.
2. User taps Share → "Save to Clipboard"
3. Extension shows preview with retention policy picker (7d / 90d / Forever)
4. User taps Save → item appears in ClipboardViewer and syncs to Mac

**Key considerations:**
- Share extensions are separate targets (like the keyboard)
- Need App Groups to share SwiftData store with main app
- Should support saving with different retention policies
- Auto-dismiss after save with confirmation

### Architecture Notes

Both extensions would require:
- **App Groups** configured for all targets (main app + keyboard + share)
- **Shared SwiftData container** accessible from extensions
- Extensions are separate Xcode targets within the same project

**Open questions:**
- [ ] Should keyboard show ALL synced items or just "pinned" / high-retention items?
- [ ] Should share extension default to "temporary" (7d) or ask every time?
- [ ] How to handle the iOS clipboard monitoring limitation? (Can't auto-capture like macOS)

---

## Paused At

**Current state:** Phase 4 complete, both targets build. Phase 5 (iCloud setup) is next.

**Next steps when resuming:**
1. Complete Phase 5 (CloudKit configuration in Xcode)
2. Complete Phase 6 (wire macOS app to SwiftData)
3. Test sync between macOS and iOS
4. Design and implement iOS extensions
