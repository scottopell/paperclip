import AppKit
import KeyboardShortcuts
import SwiftUI

/// Manages keyboard shortcut preferences
class KeyboardShortcutsManager {
    static let shared = KeyboardShortcutsManager()
    private var preferencesWindow: NSWindow?

    private init() {}

    func showPreferences() {
        // If window exists, just bring it to front
        if let window = preferencesWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Create a new window
        let preferencesView = KeyboardShortcutsView()
        let hostingController = NSHostingController(rootView: preferencesView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Keyboard Shortcuts"
        window.contentView = hostingController.view
        window.center()

        self.preferencesWindow = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

struct KeyboardShortcutsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Configure Keyboard Shortcuts")
                .font(.headline)
                .padding(.bottom, 8)

            VStack(alignment: .leading) {
                Text("Quick Search:")
                    .font(.subheadline)

                KeyboardShortcuts.Recorder(for: .toggleQuickSearch)
                    .padding(.leading, 8)
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 400, minHeight: 200)
    }
}
