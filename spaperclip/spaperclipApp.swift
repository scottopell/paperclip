//
//  spaperclipApp.swift
//  spaperclip
//
//  Created by Scott Opell on 5/3/25.
//

// MARK: - App
import SwiftUI

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
