# sPaperclip

sPaperclip is a small macOS clipboard-history app. While it is running, it records up to 100 recent clipboard items, persists them locally, and lets you search and restore them.

## MVP features

- Clipboard history with timestamp and best-effort source-app metadata
- Local Core Data persistence across app launches
- Text, image, PDF, URL, and other pasteboard-format capture
- Search in the main window
- Quick Search from other apps with a configurable global shortcut
- Full-format copy with Enter; plain-text-only copy with Shift+Enter
- Menu bar access to storage statistics and history clearing

## Requirements

- macOS 15.0 or later
- Xcode 16 or later to build from source

sPaperclip must be running to monitor the clipboard or respond to its global shortcut. Launch at login is not part of the current MVP.

## Build from source

The Xcode project is the authoritative build. It resolves the pinned `KeyboardShortcuts` Swift package automatically.

```sh
xcodebuild \
  -project spaperclip.xcodeproj \
  -scheme spaperclip \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData \
  build
```

For a release app:

```sh
xcodebuild \
  -project spaperclip.xcodeproj \
  -scheme spaperclip \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData \
  build
```

The release product is `.build/DerivedData/Build/Products/Release/spaperclip.app`.

## Tests

Run unit tests without launching the UI-test runner:

```sh
xcodebuild \
  -project spaperclip.xcodeproj \
  -scheme spaperclip \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData \
  -only-testing:spaperclipTests \
  test
```

Run the focused performance gates (one warmup plus five raw samples per workload):

```sh
xcodebuild \
  -project spaperclip.xcodeproj \
  -scheme spaperclip \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData \
  DEVELOPMENT_TEAM= \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  AD_HOC_CODE_SIGNING_ALLOWED=YES \
  -parallel-testing-enabled NO \
  -only-testing:spaperclipTests/PerformanceTests \
  test
```

The performance tests print their configuration, raw samples, and median. Use a consistent machine and configuration for comparisons. The ad-hoc workspace cannot load the project's Release test bundle because macOS requires its host and test bundle to have matching development-team signatures; optimized standalone measurements established the original baseline and candidate, while these production-path XCTest gates provide repeatable regression limits.

Run the accessibility-driven UI tests with local ad-hoc signing:

```sh
xcodebuild \
  -project spaperclip.xcodeproj \
  -scheme spaperclip \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath .build/XCUITestDerivedData \
  DEVELOPMENT_TEAM= \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  AD_HOC_CODE_SIGNING_ALLOWED=YES \
  -only-testing:spaperclipUITests/spaperclipUITests/testLaunchShowsEmptyClipboardHistory \
  -only-testing:spaperclipUITests/spaperclipUITests/testCaptureSearchAndRestoreText \
  -only-testing:spaperclipUITests/spaperclipUITests/testQuickSearchKeyboardJourney \
  -only-testing:spaperclipUITests/spaperclipUITests/testQuickSearchPlainTextRestore \
  test
```

The app uses a separate, freshly reset Core Data store when `SPAPERCLIP_UI_TEST_ID` is supplied by these tests, so UI automation does not read or clear normal clipboard history. Do not set `CODE_SIGNING_ALLOWED=NO` for UI tests: macOS cannot launch an unsigned XCUITest runner.

XCUITest reliably covers the same Quick Search panel through its menu command, including focus, filtering, navigation, restore, reinvocation, and dismissal. macOS does not deliver the library's global hotkey from XCUITest's synthetic Finder keystroke, so the configured shortcut from another app remains one manual acceptance check.

## Quick Search

1. Keep sPaperclip running.
2. Press **Control+Option+Space** from any application (the default).
3. Type an exact phrase or fuzzy abbreviation to rank matching clipboard history.
4. Use the arrow keys to select a result.
5. Press **Enter** to copy every captured representation, or **Shift+Enter** for plain text only. The restored item becomes the current, most-recent history entry.
6. Press **Escape** to dismiss without copying.

Change or clear the shortcut under **sPaperclip → Settings…** (`Cmd+,`).
Printable-key shortcuts follow their character when switching keyboard layouts (for example, `S` remains `S` between US and Dvorak). After upgrading from an older build, record the shortcut once more so sPaperClip can remember the intended character.

## Current limitations

- History is capped at 100 items.
- Source application detection is best effort.
- Large rich-text/HTML values may have limited previews even though their pasteboard data is retained.
- The app is not configured to launch at login.
- Distribution signing, notarization, and DMG packaging are not automated.
