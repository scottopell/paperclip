import AppKit
import SwiftUI

/// Manages the menubar item for the application
class MenuBarManager: ObservableObject {
    static let shared = MenuBarManager()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    private init() {}

    /// Sets up the menu bar item with the statistics view
    func setupMenuBar() {
        // Create the status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: "chart.bar.doc.horizontal",
                accessibilityDescription: "sPaperclip Stats")
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Create the popover
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 400, height: 500)
        popover?.behavior = .transient
        popover?.animates = true

        // Set the SwiftUI view as content
        let contentView = CoreDataStatsView()
        popover?.contentViewController = NSHostingController(rootView: contentView)
    }

    /// Toggles the popover when clicking the menu bar item
    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        guard let popover = popover else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            if let button = statusItem?.button {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }
}
