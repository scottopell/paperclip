import AppKit
import ApplicationServices
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
    private var activationObserver: NSObjectProtocol?
    private var lastExternalApplication: NSRunningApplication?
    private var pasteTarget: NSRunningApplication?

    private init() {
        rememberExternalApplication(NSWorkspace.shared.frontmostApplication)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let application = notification.userInfo?[
                NSWorkspace.applicationUserInfoKey
            ] as? NSRunningApplication
            Task { @MainActor in
                self?.rememberExternalApplication(application)
            }
        }
    }

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
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        rememberExternalApplication(frontmostApplication)
        pasteTarget = isPaperclip(frontmostApplication)
            ? lastExternalApplication
            : frontmostApplication
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

    /// Hides Quick Search and sends Command-V directly to the application that owned
    /// focus before invocation. Accessibility permission is requested only on this path.
    func pasteIntoInvokingApplication() -> String? {
        guard let target = pasteTarget, !target.isTerminated else {
            return "Copied to the clipboard, but there is no previous app to paste into."
        }

        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        guard AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary) else {
            return "Copied to the clipboard. Allow Accessibility access to paste automatically."
        }

        guard let pasteKeyCode = LayoutAwareShortcutManager.keyCode(for: "v"),
            let source = CGEventSource(stateID: .hidSystemState),
            let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(pasteKeyCode),
                keyDown: true
            ),
            let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(pasteKeyCode),
                keyDown: false
            )
        else {
            return "Copied to the clipboard, but the paste keystroke could not be created."
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        hideQuickSearch()
        _ = target.activate(options: [.activateIgnoringOtherApps])
        keyDown.postToPid(target.processIdentifier)
        keyUp.postToPid(target.processIdentifier)
        return nil
    }

    private func rememberExternalApplication(_ application: NSRunningApplication?) {
        guard let application, !isPaperclip(application) else { return }
        lastExternalApplication = application
    }

    private func isPaperclip(_ application: NSRunningApplication?) -> Bool {
        application?.bundleIdentifier == Bundle.main.bundleIdentifier
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

    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
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
