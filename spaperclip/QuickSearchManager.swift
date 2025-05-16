import AppKit
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let toggleQuickSearch = Self(
        "toggleQuickSearch", default: .init(.space, modifiers: [.command, .shift]))
}

/// Manages the quick search functionality
class QuickSearchManager: ObservableObject {
    static let shared = QuickSearchManager()

    @Published var isQuickSearchVisible = false
    private var window: NSPanel?
    private var sharedClipboardMonitor: ClipboardMonitor?

    private init() {
        setupKeyboardShortcut()
    }

    private func setupKeyboardShortcut() {
        KeyboardShortcuts.onKeyDown(for: .toggleQuickSearch) { [weak self] in
            self?.toggleQuickSearch()
        }
    }

    func setSharedMonitor(_ monitor: ClipboardMonitor) {
        self.sharedClipboardMonitor = monitor
    }

    func toggleQuickSearch() {
        if let window = self.window, window.isVisible {
            hideQuickSearch()
        } else {
            showQuickSearch()
        }
    }

    func showQuickSearch() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let monitor = self.sharedClipboardMonitor else {
                print("Error: Shared ClipboardMonitor not set in QuickSearchManager")
                return
            }

            if let window = self.window {
                NSApp.activate(ignoringOtherApps: true)  // Ensure app is active
                window.alphaValue = 1.0  // Reset alpha value
                window.center()  // Recenter if already exists
                window.orderFront(nil)  // Bring to front
                window.makeKey()  // Make window key explicitly
                self.isQuickSearchVisible = true  // Update visibility state
                return
            }

            let quickSearchView = QuickSearchView(monitor: monitor)
            let hostingController = NSHostingController(rootView: quickSearchView)

            let window = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                styleMask: [.titled, .closable, .resizable],  // Allow becoming key
                backing: .buffered,
                defer: false
            )

            window.titleVisibility = .hidden  // Hide the title bar
            window.titlebarAppearsTransparent = true  // Make titlebar transparent
            window.isFloatingPanel = true  // Makes it float above other windows
            window.becomesKeyOnlyIfNeeded = false  // Crucial: allows the panel to become key
            window.acceptsMouseMovedEvents = true

            window.level = .floating  // Keep it above most other windows
            window.isOpaque = false  // Necessary for transparency and custom shapes
            window.backgroundColor = .clear  // Let the SwiftUI view define the background
            window.hasShadow = true  // Add a system shadow to the borderless window
            window.isMovableByWindowBackground = true  // Allow dragging
            // Behavior for spaces and fullscreen apps.
            // .moveToActiveSpace is typically implicit with .canJoinAllSpaces when shown.
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            window.contentView = hostingController.view
            window.center()

            // If QuickSearchView itself has a rounded background (e.g., via its VisualEffectView),
            // this helps ensure the window corners clip correctly.
            hostingController.view.wantsLayer = true
            hostingController.view.layer?.masksToBounds = true
            // For explicit corner radius on the window content, you might apply it to the hostingController.view.layer
            // e.g., hostingController.view.layer?.cornerRadius = 12 // Adjust as needed

            self.window = window
            NSApp.activate(ignoringOtherApps: true)  // Activate app
            window.orderFront(nil)  // Show window
            window.makeKey()  // Make window key explicitly

            self.isQuickSearchVisible = true
        }
    }

    func hideQuickSearch() {
        guard let window = self.window else { return }

        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0.2
        NSAnimationContext.current.completionHandler = {
            window.orderOut(nil)
            self.isQuickSearchVisible = false
        }
        window.animator().alphaValue = 0.0
        NSAnimationContext.endGrouping()
    }
}
