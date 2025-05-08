//
//  spaperclipApp.swift
//  spaperclip
//
//  Created by Scott Opell on 5/4/25.
//

import SwiftUI

// MARK: - App

/// Main application structure
@main
struct ClipboardViewerApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 600, minHeight: 400)
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    if newPhase == .background || newPhase == .inactive {
                        // Save Core Data context when app moves to background
                        CoreDataManager.shared.saveViewContext()
                    }
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
            }
        }
    }
}
