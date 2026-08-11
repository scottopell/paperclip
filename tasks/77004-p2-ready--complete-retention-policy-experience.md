Phase 8 of the cross-device clipboard-sync rollout. Depends on verified CloudKit sync.

Scope:
- spaperclip/ClipboardDetailView.swift: add controls for 7-day, 90-day, and permanent retention.
- ClipboardViewer-iOS/ContentView.swift: present the synced policy consistently and hide expired records.
- Shared/ClipboardItem.swift and Shared/RetentionPolicy.swift: make policy changes and expiration behavior deterministic.
- spaperclipTests/: cover policy transitions and expiration boundaries.

Acceptance:
- A retention change made on macOS syncs to iOS.
- Temporary items disappear after expiration, while permanent items remain visible.
- Policy labels and dates agree on both platforms.
- Boundary tests cover all three retention policies.

Out of scope: custom keyboard and share extensions; those remain speculative until separately designed.
