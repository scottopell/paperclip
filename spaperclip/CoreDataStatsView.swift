import CoreData
import SwiftUI

struct CoreDataStatsView: View {
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
                .controlSize(.small)

                Button(action: clearAllData) {
                    Text("Clear All Data")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
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
        .onAppear {
            refreshStats()
        }
    }

    private func refreshStats() {
        isRefreshing = true

        DispatchQueue.global(qos: .userInitiated).async {
            // Get all statistics in one call
            let stats = coreDataManager.getStoreStatistics()

            // Format date values
            let newestDateStr =
                stats.newestItemDate != nil
                ? dateFormatter.string(from: stats.newestItemDate!) : "N/A"
            let oldestDateStr =
                stats.oldestItemDate != nil
                ? dateFormatter.string(from: stats.oldestItemDate!) : "N/A"

            // Update the UI on the main thread
            DispatchQueue.main.async {
                totalItems = stats.totalItems
                mainStoreSize = stats.formatSize(stats.storeSizeBytes)
                binaryDataSize = stats.formatSize(stats.binaryDataSizeBytes)
                storeLocation = stats.storeLocation
                newestItem = newestDateStr
                oldestItem = oldestDateStr
                debugInfo = stats.debugInfo
                isRefreshing = false
            }
        }
    }

    private func clearAllData() {
        // Show confirmation dialog
        let alert = NSAlert()
        alert.messageText = "Clear All Clipboard Data"
        alert.informativeText =
            "Are you sure you want to delete all clipboard history? This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Clear All Data")

        if let window = NSApplication.shared.windows.first {
            alert.beginSheetModal(for: window) { response in
                if response == .alertSecondButtonReturn {
                    coreDataManager.clearAllData()
                    // Refresh stats after clearing
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        refreshStats()
                    }
                }
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
