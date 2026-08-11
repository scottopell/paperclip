Phase 5 of the cross-device clipboard-sync rollout. Depends on the iOS companion foundation PR.

Scope:
- spaperclip/spaperclip.entitlements: enable CloudKit for iCloud.com.scottopell.spaperclip.
- ClipboardViewer-iOS/ClipboardViewer.entitlements: enable the same CloudKit container for the iOS target.
- spaperclip.xcodeproj/project.pbxproj: attach the capabilities and entitlement files to both application targets.

Acceptance:
- The macOS and iOS targets both build under team X2ULA6KJUN.
- The signed products declare the same iCloud container and CloudKit service.
- No certificate, private key, or Apple credential is committed.

Out of scope: persisting macOS clipboard captures into SwiftData; end-to-end device sync verification.
