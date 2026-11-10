import AppKit
import SwiftUI

/// Owns the main Clipboard History window for the lifetime of the application.
/// AppKit, rather than a transient SwiftUI scene, controls close and reopen behavior.
@MainActor
final class ClipboardHistoryWindowController: NSWindowController, NSWindowDelegate {
    private let monitor: ClipboardMonitor
    private let hostingController: NSHostingController<ContentView>

    init(monitor: ClipboardMonitor) {
        self.monitor = monitor

        let rootView = ContentView(clipboardMonitor: monitor)
        let hostingController = NSHostingController(rootView: rootView)
        self.hostingController = hostingController
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Clipboard History"
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self
        shouldCascadeWindows = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showHistory() {
        guard let window else { return }
        NSApplication.shared.activate()
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hostingController.rootView.isHistoryActive = false
        sender.orderOut(nil)
        return false
    }

    func windowDidBecomeKey(_ notification: Notification) {
        hostingController.rootView.isHistoryActive = true
    }

    func windowDidResignKey(_ notification: Notification) {
        hostingController.rootView.isHistoryActive = false
    }
}
