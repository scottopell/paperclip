# Paperclip

Paperclip is a small macOS clipboard-history app. While it is running, it records up to 100 recent clipboard items, persists them locally, and lets you search and restore them.

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

Paperclip must be running to monitor the clipboard or respond to its global shortcut. Launch at login is not part of the current MVP.

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

The release product is `.build/DerivedData/Build/Products/Release/spaperclip.app`. Local builds remain useful for development, but they are not the stable distribution identity used by macOS Accessibility. On machines without Apple credentials, use the ad-hoc command-line overrides shown under Tests.

## Signed GitHub releases

Version tags publish a Developer ID-signed, notarized ZIP through `.github/workflows/release.yml`. This is the daily-use build for both Macs. The work Mac needs neither an Apple ID nor signing credentials: download `Paperclip-macOS.zip`, replace `/Applications/spaperclip.app`, and approve Accessibility on its first signed installation.

The stable Accessibility identity depends on keeping the Developer ID team and `com.scottopell.spaperclip` bundle identifier unchanged—not merely on the app name. Continue installing updates at `/Applications/spaperclip.app` and do not replace the daily-use app with an ad-hoc development build.

### One-time setup on the personal Mac

An active Apple Developer Program membership is required.

1. In Certificates, Identifiers & Profiles, create a **Developer ID Application** certificate. Install it and its private key in Keychain Access.
2. Export the certificate and private key as a password-protected `.p12`, then encode it without line wrapping:

   ```sh
   base64 -i DeveloperIDApplication.p12 | tr -d '\n' > DeveloperIDApplication.p12.base64
   ```

3. In App Store Connect, create a team API key with permission to submit software for notarization. Download its `AuthKey_<KEY_ID>.p8` file; Apple only offers this download once.
4. Add these GitHub repository secrets under **Settings → Secrets and variables → Actions**:

   | Secret | Value |
   | --- | --- |
   | `DEVELOPER_ID_P12_BASE64` | Contents of `DeveloperIDApplication.p12.base64` |
   | `DEVELOPER_ID_P12_PASSWORD` | Password chosen during `.p12` export |
   | `APPLE_TEAM_ID` | Ten-character Apple Developer team ID |
   | `APP_STORE_CONNECT_ISSUER_ID` | App Store Connect API issuer UUID |
   | `APP_STORE_CONNECT_KEY_ID` | API key ID |
   | `APP_STORE_CONNECT_API_KEY` | Entire `.p8` file, including BEGIN/END lines |

The workflow imports the certificate into an ephemeral keychain, writes the API key under the runner's temporary directory, and removes both in its cleanup step. No credential belongs in the repository or on the work Mac.

### Publish

Create a semantic version tag from a reviewed commit and push it:

```sh
git tag v1.0.0
git push origin v1.0.0
```

The workflow derives `CFBundleShortVersionString` from the tag, uses the GitHub run number as the build number, verifies the Developer ID signature and hardened runtime, notarizes and staples the app, runs Gatekeeper assessment, and attaches the ZIP plus its SHA-256 file to the matching GitHub Release.

Before relying on retained Accessibility trust, perform one certificate-backed two-version check:

1. Install release A at `/Applications/spaperclip.app` and approve it under **System Settings → Privacy & Security → Accessibility**.
2. Confirm Quick Search Enter pastes into the invoking app.
3. Publish release B through the same workflow and replace release A at the same path.
4. Confirm Quick Search Enter still auto-pastes without removing or re-adding Paperclip in Accessibility.

Notarization and TCC continuity cannot be proven by pull-request CI without the repository secrets and two real signed releases, so this check remains a release acceptance step.

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
  -only-testing:spaperclipUITests/spaperclipUITests/testQuietLaunchAndOpenClipboardHistory \
  -only-testing:spaperclipUITests/spaperclipUITests/testCaptureSearchAndRestoreText \
  -only-testing:spaperclipUITests/spaperclipUITests/testQuickSearchKeyboardJourney \
  -only-testing:spaperclipUITests/spaperclipUITests/testQuickSearchPlainTextRestore \
  test
```

The app uses a separate, freshly reset Core Data store when `SPAPERCLIP_UI_TEST_ID` is supplied by these tests, so UI automation does not read or clear normal clipboard history. Do not set `CODE_SIGNING_ALLOWED=NO` for UI tests: macOS cannot launch an unsigned XCUITest runner.

XCUITest reliably covers the same Quick Search panel through its menu command, including focus, filtering, navigation, restore, reinvocation, and dismissal. macOS does not deliver the library's global hotkey from XCUITest's synthetic Finder keystroke, so the configured shortcut from another app remains one manual acceptance check.

## Quick Search

1. Keep Paperclip running.
2. Press **Control+Option+Space** from any application (the default).
3. Type an exact phrase or fuzzy abbreviation to rank matching clipboard history.
4. Use the arrow keys to select a result.
5. Press **Enter** to restore every captured representation and paste it into the app you were using, or **Shift+Enter** to paste plain text only. The restored item also becomes the current, most-recent clipboard entry.
6. Press **Escape** to dismiss without copying.

Change or clear the shortcut under **Paperclip → Settings…** (`Cmd+,`). Automatic paste requires Accessibility access; if access is unavailable, Paperclip still updates the clipboard and explains why it could not paste.
Closing Clipboard History hides its AppKit-owned window while Paperclip keeps monitoring. Use the menu-bar icon to open Clipboard History, Quick Search, Database Statistics, or quit the app.
Printable-key shortcuts follow their character when switching keyboard layouts (for example, `S` remains `S` between US and Dvorak). After upgrading from an older build, record the shortcut once more so Paperclip can remember the intended character.

## Current limitations

- History is capped at 100 items.
- Source application detection is best effort.
- Large rich-text/HTML values may have limited previews even though their pasteboard data is retained.
- The app is not configured to launch at login.
- Signed and notarized ZIP releases require the repository's Apple credentials; DMG packaging and automatic updates are intentionally not included.
