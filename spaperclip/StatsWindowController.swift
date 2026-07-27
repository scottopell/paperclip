import AppKit
import SwiftUI

/// Manages the statistics window
class StatsWindowController {
    static let shared = StatsWindowController()

    private var window: NSWindow?

    private init() {}

    /// Shows the statistics window or brings it to front if already open
    func showStatsWindow(clipboardMonitor: ClipboardMonitor) {
        // If window exists, just bring it to front
        if let window = self.window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Create a new window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)

        window.title = "Database Statistics"
        window.center()
        let hostingController = NSHostingController(
            rootView: CoreDataStatsView(onClearHistory: clipboardMonitor.clearHistory)
        )
        // The window owns its size. Prevent SwiftUI's changing stats/disclosure content
        // from resizing the window during AppKit's constraint-update cycle.
        hostingController.sizingOptions = []
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 400, height: 400)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }
}
