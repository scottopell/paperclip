//
//  ContentView.swift
//  ClipboardViewer
//
//  Main view for iOS app - displays synced clipboard history.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \ClipboardItem.timestamp, order: .reverse)
    private var allItems: [ClipboardItem]

    /// Filter out expired items (can't use Date() in #Predicate)
    private var items: [ClipboardItem] {
        allItems.filter { !$0.isExpired }
    }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    emptyState
                } else {
                    itemsList
                }
            }
            .navigationTitle("Clipboard")
        }
    }

    // MARK: - Views

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Clipboard Items", systemImage: "doc.on.clipboard")
        } description: {
            Text("Items copied on your Mac will appear here.")
        }
    }

    private var itemsList: some View {
        List {
            ForEach(items) { item in
                NavigationLink(destination: ItemDetailView(item: item)) {
                    ItemRow(item: item)
                }
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - Item Row

struct ItemRow: View {
    let item: ClipboardItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.previewText)
                .font(.body)
                .lineLimit(2)

            HStack {
                Text(item.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                retentionBadge
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var retentionBadge: some View {
        switch item.retentionPolicy {
        case .permanent:
            Label("Forever", systemImage: "pin.fill")
                .font(.caption2)
                .foregroundStyle(.blue)
        case .extended:
            Label("90d", systemImage: "clock")
                .font(.caption2)
                .foregroundStyle(.orange)
        case .temporary:
            EmptyView() // Default, no badge needed
        }
    }
}

// MARK: - Item Detail View

struct ItemDetailView: View {
    let item: ClipboardItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Full text content
                if let text = item.text {
                    Text(text)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()

                // Metadata
                metadataSection
            }
            .padding()
        }
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    copyToClipboard()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Captured") {
                Text(item.timestamp, style: .date)
                Text(item.timestamp, style: .time)
            }

            LabeledContent("Retention") {
                Text(item.retentionPolicy.displayName)
            }

            if let expiration = item.expirationDate {
                LabeledContent("Expires") {
                    Text(expiration, style: .relative)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func copyToClipboard() {
        guard let text = item.text else { return }
        UIPasteboard.general.string = text
    }
}

#Preview {
    ContentView()
        .modelContainer(for: ClipboardItem.self, inMemory: true)
}
