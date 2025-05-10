import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var clipboardMonitor = ClipboardMonitor()

    var body: some View {
        NavigationSplitView {
            ZStack {
                HistoryListView(monitor: clipboardMonitor)

                if clipboardMonitor.isLoadingHistory {
                    VStack {
                        ProgressView()
                            .controlSize(.large)
                        Text("Loading history...")
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
                }
            }
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
