import AppKit
import SwiftUI

/// Manages the menubar item for the application
@MainActor
class MenuBarManager: ObservableObject {
    static let shared = MenuBarManager()

    private var statusItem: NSStatusItem?
    private weak var clipboardMonitor: ClipboardMonitor?
    private var onOpenHistory: (() -> Void)?

    private init() {}

    /// Sets up the menu bar item with the statistics view
    func setupMenuBar(
        clipboardMonitor: ClipboardMonitor,
        onOpenHistory: @escaping () -> Void
    ) {
        self.clipboardMonitor = clipboardMonitor
        self.onOpenHistory = onOpenHistory
        guard statusItem == nil else { return }
        // Create the status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: "chart.bar.doc.horizontal",
                accessibilityDescription: "sPaperclip Stats")
            button.setAccessibilityIdentifier("stats.menu-bar")
        }

        let menu = NSMenu()
        menu.addItem(
            withTitle: "Open Clipboard History",
            action: #selector(openHistoryFromMenu),
            keyEquivalent: ""
        ).target = self
        menu.addItem(
            withTitle: "Quick Search",
            action: #selector(openQuickSearchFromMenu),
            keyEquivalent: ""
        ).target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Database Statistics",
            action: #selector(openStatisticsFromMenu),
            keyEquivalent: ""
        ).target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit sPaperclip",
            action: #selector(quitFromMenu),
            keyEquivalent: "q"
        ).target = self
        statusItem?.menu = menu

    }

    @objc private func openHistoryFromMenu() {
        onOpenHistory?()
    }

    @objc private func openQuickSearchFromMenu() {
        QuickSearchManager.shared.showQuickSearch()
    }

    @objc private func openStatisticsFromMenu() {
        guard let clipboardMonitor else { return }
        StatsWindowController.shared.showStatsWindow(clipboardMonitor: clipboardMonitor)
    }

    @objc private func quitFromMenu() {
        NSApplication.shared.terminate(nil)
    }
}
