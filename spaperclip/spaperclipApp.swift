//
//  spaperclipApp.swift
//  spaperclip
//
//  Created by Scott Opell on 5/4/25.
//

import AppKit
import SwiftUI

// MARK: - App

/// Main application structure
@main
struct ClipboardViewerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var menuBarManager = MenuBarManager.shared
    @StateObject private var clipboardMonitor = ClipboardMonitor()

    var body: some Scene {
        WindowGroup {
            ContentView(clipboardMonitor: clipboardMonitor)
                .frame(minWidth: 600, minHeight: 400)
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .background || newPhase == .inactive {
                        // Save Core Data context when app moves to background
                        CoreDataManager.shared.saveViewContext()
                    }
                }
                .onAppear {
                    // Setup the menu bar item
                    menuBarManager.setupMenuBar()
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

                Button("Database Statistics") {
                    StatsWindowController.shared.showStatsWindow()
                }
                .keyboardShortcut("D", modifiers: [.command, .option])
            }
        }
    }
}
