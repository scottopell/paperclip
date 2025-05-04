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
                    // TODO
                }
                .keyboardShortcut("K", modifiers: [.command, .shift])
            }
        }
    }
}
