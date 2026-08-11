# Publish stable signed and notarized GitHub Releases

## Why

Paperclip's automatic paste posts Command-V through `CGEvent`, which requires macOS Accessibility trust. The project currently forces ad-hoc signing, so rebuilt binaries do not retain a stable code identity and macOS repeatedly requires Paperclip to be added back to Accessibility. The sole user develops on two Macs and does not want a personal Apple ID configured on the work Mac.

A Developer ID-signed, notarized release downloaded from GitHub gives Paperclip a stable designated requirement across updates. The work Mac can install published binaries without holding Apple credentials, while preserving the fast Quick Search auto-paste loop.

## Scope

- Replace the placeholder Linux release workflow with a macOS workflow that builds the authoritative Xcode project on version tags.
- Import a Developer ID Application certificate from encrypted GitHub Actions secrets into an ephemeral keychain.
- Build the Release app with the stable bundle identifier `com.scottopell.spaperclip`, the configured development team, hardened runtime, and Developer ID signing.
- Submit the signed app to Apple's notary service, wait for success, and staple the notarization ticket.
- Validate the artifact with `codesign` and `spctl` before publishing it.
- Package the stapled app in a macOS-safe archive and attach it to a GitHub Release.
- Document the one-time personal-Mac setup: Apple Developer Program prerequisites, certificate/P12 export, App Store Connect API key or equivalent notary credentials, exact GitHub secret names, tagging a release, installation into `/Applications`, and first-run Accessibility approval.
- Remove the project-level forced ad-hoc identity from production app configurations if it prevents explicit Developer ID signing. Keep local tests able to opt into ad-hoc signing through their existing command-line overrides.
- Create a **draft pull request** containing the implementation and setup documentation so certificate-backed release testing can resume from the personal Mac before merge.

## Explicit non-goals

- No Apple ID, signing certificate, or private key is installed on the work Mac.
- No credentials are committed to the repository or included in release artifacts.
- No Sparkle or automatic updater.
- No DMG unless it is demonstrably simpler than a notarized ZIP; prefer the smallest safe artifact.
- No Mac App Store distribution.
- No change to clipboard capture or automatic-paste behavior.

## Secret interface

Use a small, documented set of repository or environment secrets. Prefer App Store Connect API-key notarization because it is revocable and does not store an Apple ID password. The implementation should define and document names for:

- Base64-encoded Developer ID Application `.p12`
- `.p12` password
- Developer team ID
- App Store Connect issuer ID
- App Store Connect key ID
- App Store Connect private API key

If repository variables are appropriate for non-sensitive identifiers, document that distinction rather than treating every value as secret.

## Acceptance checks

- A tag-triggered workflow builds on a GitHub-hosted macOS runner without any signing material in the repository.
- The resulting archive contains Paperclip signed by the expected Developer ID identity with hardened runtime enabled.
- `codesign --verify --deep --strict --verbose=2` succeeds.
- Notarization succeeds and `xcrun stapler validate` succeeds.
- `spctl --assess --type execute --verbose` accepts the app.
- The archive is attached to the matching GitHub Release rather than requiring manual upload.
- Setup documentation is sufficient to configure secrets from the personal Mac.
- Manual two-version acceptance check: install release A into `/Applications`, approve Accessibility once, replace it with release B signed through the same pipeline, and confirm automatic paste still works without re-adding Accessibility permission.
- A draft PR is opened with the workflow, documentation, validation evidence available without secrets, and a clearly marked certificate-dependent verification checklist.

## Implementation note

Do not claim that bundle ID alone preserves TCC approval. Stability depends on the signed app's designated requirement, particularly the same Developer ID/team identity and bundle identifier. Keep the app path stable as an operational precaution and avoid ad-hoc builds for daily use on the work Mac.
