import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var clipboardMonitor: ClipboardMonitor
    @State private var detailWidth: CGFloat = 300
    @State private var minDetailWidth: CGFloat = 250

    var body: some View {
        HSplitView {
            // History list - the main focus of the app
            ZStack {
                HistoryListView(monitor: clipboardMonitor)
                    .frame(minWidth: 250, idealWidth: 350)

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

            // Detail view (resizable but can be minimized, not hidden)
            ClipboardDetailView(monitor: clipboardMonitor)
                .frame(minWidth: minDetailWidth, idealWidth: detailWidth)
        }
        .toolbar {
            // Main toolbar title/info in the navigation area
            ToolbarItem(placement: .principal) {
                ToolbarMetadataView(monitor: clipboardMonitor)
            }

            // Copy button
            ToolbarItem {
                Button {
                    if let item = clipboardMonitor.selectedHistoryItem {
                        Utilities.copyAllContentTypes(from: item)
                    }
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .disabled(clipboardMonitor.selectedHistoryItem == nil)
                .help("Copy to Clipboard")
            }
        }
        .navigationTitle("sPaperClip")
        .onDisappear {
            clipboardMonitor.stopMonitoring()
        }
    }
}
