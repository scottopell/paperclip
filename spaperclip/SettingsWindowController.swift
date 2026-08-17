import AppKit
import SwiftUI

/// Owns the Settings window for the lifetime of the application.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    init() {
        let hostingController = NSHostingController(rootView: ShortcutSettingsView())
        hostingController.sizingOptions = []

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 180),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Paperclip Settings"
        window.contentViewController = hostingController
        window.setContentSize(NSSize(width: 460, height: 180))
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showSettings() {
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
