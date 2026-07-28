import AppKit
import KeyboardShortcuts
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let clipboardMonitor = ClipboardMonitor()
    private lazy var historyWindowController = ClipboardHistoryWindowController(
        monitor: clipboardMonitor
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        QuickSearchManager.shared.setSharedMonitor(clipboardMonitor)
        LayoutAwareShortcutManager.shared.start()
        MenuBarManager.shared.setupMenuBar(
            clipboardMonitor: clipboardMonitor,
            onOpenHistory: { [weak self] in
                self?.historyWindowController.showHistory()
            }
        )
        historyWindowController.showHistory()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardMonitor.stopMonitoring()
        CoreDataManager.shared.saveViewContext()
    }
}

@main
struct ClipboardViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            ShortcutSettingsView()
        }
    }
}
