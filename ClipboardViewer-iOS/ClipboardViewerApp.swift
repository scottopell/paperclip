//
//  ClipboardViewerApp.swift
//  ClipboardViewer
//
//  iOS companion app for spaperclip.
//  Displays clipboard history synced from macOS via iCloud.
//

import SwiftUI
import SwiftData

@main
struct ClipboardViewerApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([ClipboardItem.self])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
