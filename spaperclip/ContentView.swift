import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var clipboardMonitor = ClipboardMonitor()

    var body: some View {
        NavigationSplitView {
            HistoryListView(monitor: clipboardMonitor)
        } detail: {
            ClipboardDetailView(
                monitor: clipboardMonitor,
            )
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
        .onDisappear {
            clipboardMonitor.stopMonitoring()
        }
    }
}
