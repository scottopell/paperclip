import CoreData
import SwiftUI

enum ClearHistoryConfirmation {
    static let title = "Clear Clipboard History?"
    static let message = "This permanently deletes all clipboard history. This action cannot be undone."

    static func present(for window: NSWindow? = NSApp.keyWindow, onConfirm: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")

        if let window {
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn { onConfirm() }
            }
        } else if alert.runModal() == .alertFirstButtonReturn {
            onConfirm()
        }
    }
}

struct CoreDataStatsView: View {
    let onClearHistory: (@escaping () -> Void) -> Void

    init(onClearHistory: @escaping (@escaping () -> Void) -> Void) {
        self.onClearHistory = onClearHistory
    }

    @State private var totalItems: Int = 0
    @State private var mainStoreSize: String = "0.00"
    @State private var binaryDataSize: String = "0.00"
    @State private var storeLocation: String = "Unknown"
    @State private var oldestItem: String = "N/A"
    @State private var newestItem: String = "N/A"
    @State private var isRefreshing: Bool = false
    @State private var showDebugDetails: Bool = false
    @State private var debugInfo: String = ""

    private let coreDataManager = CoreDataManager.shared
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Core Data Statistics")
                .font(.headline)
                .padding(.bottom, 4)

            Group {
                StatRow(label: "Total Items", value: "\(totalItems)")
                StatRow(label: "Main DB Size", value: "\(mainStoreSize) MiB")
                StatRow(label: "Binary Data Size", value: "\(binaryDataSize) MiB")
                StatRow(label: "Store Location", value: storeLocation)
                    .lineLimit(1)
                    .truncationMode(.middle)
                StatRow(label: "Newest Item", value: newestItem)
                StatRow(label: "Oldest Item", value: oldestItem)
            }

            HStack {
                Spacer()
                Button(action: refreshStats) {
                    HStack {
                        Text("Refresh")
                        if isRefreshing {
                            ProgressView()
                                .scaleEffect(0.7)
                                .progressViewStyle(CircularProgressViewStyle())
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("stats.refresh")
                .controlSize(.small)
                .disabled(isRefreshing)

                Button(action: clearAllData) {
                    Text("Clear All Data")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(totalItems == 0 || isRefreshing)
                .accessibilityIdentifier("stats.clear-history")
                Spacer()
            }
            .padding(.top, 8)

            Divider()

            // Debug section
            DisclosureGroup(
                isExpanded: $showDebugDetails,
                content: {
                    ScrollView {
                        Text(debugInfo)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    }
                    .frame(height: 200)
                },
                label: {
                    Text("Debug Details")
                        .font(.headline)
                }
            )
            .padding(.top, 8)
        }
        .padding()
        .frame(width: 400)
        .accessibilityIdentifier("stats.root")
        .onAppear {
            refreshStats()
        }
    }

    private func refreshStats() {
        guard !isRefreshing else { return }
        isRefreshing = true

        Task {
            let stats = await coreDataManager.getStoreStatistics()
            totalItems = stats.totalItems
            mainStoreSize = stats.formatSize(stats.storeSizeBytes)
            binaryDataSize = stats.formatSize(stats.binaryDataSizeBytes)
            storeLocation = stats.storeLocation
            newestItem = stats.newestItemDate.map(dateFormatter.string) ?? "N/A"
            oldestItem = stats.oldestItemDate.map(dateFormatter.string) ?? "N/A"
            debugInfo = stats.debugInfo
            isRefreshing = false
        }
    }

    private func clearAllData() {
        guard totalItems > 0 else { return }
        ClearHistoryConfirmation.present {
            isRefreshing = true
            onClearHistory {
                isRefreshing = false
                refreshStats()
            }
        }
    }
}

struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label + ":")
                .frame(width: 100, alignment: .leading)
                .foregroundColor(.secondary)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(.body, design: .monospaced))
        .font(.footnote)
    }
}
