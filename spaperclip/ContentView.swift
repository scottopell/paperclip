import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var clipboardMonitor: ClipboardMonitor
    @ObservedObject private var quickSearchManager = QuickSearchManager.shared
    var isHistoryActive = false

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
            // The history window is retained when closed and shares Quick
            // Search's selection. Only an actively inspected history window may
            // decode and lay out its unbounded detail.
            if isHistoryActive && !quickSearchManager.isQuickSearchVisible {
                ClipboardDetailView(monitor: clipboardMonitor)
            } else {
                Color.clear
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
        .frame(minWidth: 600, minHeight: 400)
    }
}
