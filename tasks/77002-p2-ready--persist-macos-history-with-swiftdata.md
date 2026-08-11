Phase 6 of the cross-device clipboard-sync rollout. Depends on the shared CloudKit container configuration.

Scope:
- Shared/ModelContainerSetup.swift: provide one shared SwiftData/CloudKit container configuration.
- spaperclip/spaperclipApp.swift: install the shared model container in the macOS app.
- spaperclip/ClipboardMonitor.swift: persist captured text as ClipboardItem records.
- spaperclip/HistoryList.swift and spaperclip/ClipboardDetailView.swift: read the persisted history without regressing existing clipboard behavior.
- spaperclipTests/: cover persistence mapping, duplicate handling, and restart-safe history.

Acceptance:
- Copying text on macOS creates a durable ClipboardItem.
- Relaunching the macOS app retains the persisted item.
- Existing clipboard capture, search, preview, and restore tests remain green.
- Records use the schema consumed by the iOS target.

Out of scope: physical-device CloudKit acceptance testing and retention-policy controls.
