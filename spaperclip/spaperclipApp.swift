//
//  spaperclipApp.swift
//  spaperclip
//
//  Created by Scott Opell on 5/3/25.
//

import SwiftUI

// MARK: - App

/// Main application structure
@main
struct ClipboardViewerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 600, minHeight: 400)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandMenu("Clipboard") {
                Button("Clear History") {
                    // Would connect to view model to clear history
                    // This is also available from the toolbar
                }
                .keyboardShortcut("K", modifiers: [.command, .shift])
            }
        }
    }
}
