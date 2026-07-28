import AppKit
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let toggleQuickSearch = Self(
        "toggleQuickSearch", default: .init(.space, modifiers: [.control, .option]))
}

private final class QuickSearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the global shortcut and the reusable Quick Search panel.
@MainActor
final class QuickSearchManager: ObservableObject {
    static let shared = QuickSearchManager()

    @Published private(set) var isQuickSearchVisible = false
    @Published private(set) var presentationID = UUID()

    private var window: NSPanel?
    private var sharedClipboardMonitor: ClipboardMonitor?
    private var isShortcutRegistered = false

    private init() {}

    /// Installs the monitor before enabling the shortcut, so invocation can never race setup.
    func setSharedMonitor(_ monitor: ClipboardMonitor) {
        sharedClipboardMonitor = monitor
        guard !isShortcutRegistered else { return }

        KeyboardShortcuts.onKeyDown(for: .toggleQuickSearch) { [weak self] in
            Task { @MainActor in
                self?.toggleQuickSearch()
            }
        }
        isShortcutRegistered = true
    }

    func toggleQuickSearch() {
        isQuickSearchVisible ? hideQuickSearch() : showQuickSearch()
    }

    func showQuickSearch() {
        guard let monitor = sharedClipboardMonitor else { return }
        monitor.reconcileCurrentPasteboard()

        let panel = window ?? makePanel(monitor: monitor)
        window = panel

        panel.alphaValue = 1
        positionOnActiveScreen(panel)
        panel.orderFrontRegardless()
        panel.makeKey()
        isQuickSearchVisible = true

        // A new ID defines a new search session. Publishing it after the panel is
        // key lets the view reset query, selection, and focus without a timer.
        presentationID = UUID()
    }

    func hideQuickSearch() {
        guard let panel = window, panel.isVisible else {
            isQuickSearchVisible = false
            return
        }

        // Immediate ordering avoids stale animation completions hiding a newly reopened panel.
        panel.orderOut(nil)
        isQuickSearchVisible = false
    }

    private func positionOnActiveScreen(_ panel: NSPanel) {
        let pointerLocation = NSEvent.mouseLocation
        let activeScreen = NSScreen.screens.first { NSMouseInRect(pointerLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visibleFrame = activeScreen?.visibleFrame else { return }

        let origin = NSPoint(
            x: visibleFrame.midX - panel.frame.width / 2,
            y: visibleFrame.midY - panel.frame.height / 2
        )
        panel.setFrameOrigin(origin)
    }

    private func makePanel(monitor: ClipboardMonitor) -> NSPanel {
        let quickSearchView = QuickSearchView(monitor: monitor, manager: self)
        let hostingController = NSHostingController(rootView: quickSearchView)
        let panel = QuickSearchPanel(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 620),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.title = "Quick Search"
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.acceptsMouseMovedEvents = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = hostingController
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.cornerRadius = 14
        hostingController.view.layer?.masksToBounds = true
        return panel
    }
}
