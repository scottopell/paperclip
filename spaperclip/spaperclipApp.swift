import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let clipboardMonitor = ClipboardMonitor()
    private lazy var historyWindowController = ClipboardHistoryWindowController(
        monitor: clipboardMonitor
    )
    private lazy var settingsWindowController = SettingsWindowController()

    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        QuickSearchManager.shared.setSharedMonitor(clipboardMonitor)
        LayoutAwareShortcutManager.shared.start()
        MenuBarManager.shared.setupMenuBar(
            clipboardMonitor: clipboardMonitor,
            onOpenHistory: { [weak self] in
                self?.historyWindowController.showHistory()
            },
            onOpenSettings: { [weak self] in
                self?.settingsWindowController.showSettings()
            }
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardMonitor.stopMonitoring()
        CoreDataManager.shared.saveViewContext()
    }
}
