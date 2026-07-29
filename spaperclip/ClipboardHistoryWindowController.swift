import AppKit
import SwiftUI

/// Owns the main Clipboard History window for the lifetime of the application.
/// AppKit, rather than a transient SwiftUI scene, controls close and reopen behavior.
@MainActor
final class ClipboardHistoryWindowController: NSWindowController, NSWindowDelegate {
    private let monitor: ClipboardMonitor

    init(monitor: ClipboardMonitor) {
        self.monitor = monitor

        let rootView = ContentView(clipboardMonitor: monitor)
            .frame(minWidth: 600, minHeight: 400)
        let hostingController = NSHostingController(rootView: rootView)
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
        sender.orderOut(nil)
        return false
    }
}
