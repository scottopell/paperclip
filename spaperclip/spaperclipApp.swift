//
//  spaperclipApp.swift
//  spaperclip
//
//  Created by Scott Opell on 5/4/25.
//

import AppKit
import KeyboardShortcuts
import SwiftUI

// MARK: - App

/// Main application structure
@main
struct ClipboardViewerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var menuBarManager = MenuBarManager.shared
    @StateObject private var quickSearchManager = QuickSearchManager.shared
    @StateObject private var sharedClipboardMonitor = ClipboardMonitor()

    var body: some Scene {
        WindowGroup {
            ContentView(clipboardMonitor: sharedClipboardMonitor)
                .frame(minWidth: 600, minHeight: 400)
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    if newPhase == .background || newPhase == .inactive {
                        // Save Core Data context when app moves to background
                        CoreDataManager.shared.saveViewContext()
                    }
                }
                .onAppear {
                    // Setup the menu bar item
                    menuBarManager.setupMenuBar()
                    // Pass shared monitor to QuickSearchManager
                    quickSearchManager.setSharedMonitor(sharedClipboardMonitor)
                }
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandMenu("Clipboard") {
                Button("Clear History") {
                    ClipboardPersistenceManager.shared.clearAllHistory()
                }
                .keyboardShortcut("K", modifiers: [.command, .shift])

                Divider()

                Button("Quick Search") {
                    quickSearchManager.toggleQuickSearch()
                }

                Divider()

                Button("Database Statistics") {
                    StatsWindowController.shared.showStatsWindow()
                }
                .keyboardShortcut("D", modifiers: [.command, .option])
            }

            CommandMenu("Preferences") {
                Button("Keyboard Shortcuts") {
                    KeyboardShortcutsManager.shared.showPreferences()
                }
            }
        }
    }
}
