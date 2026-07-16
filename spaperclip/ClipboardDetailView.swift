//
//  ClipboardDetailView.swift
//  spaperclip
//
//  Created by Scott Opell on 5/4/25.
//

import SwiftUI

struct ClipboardDetailView: View {
    @ObservedObject var monitor: ClipboardMonitor

    // A clipboard item may contain distinct data representations, such as TIFF and PNG.
    @State private var selectedContent: ClipboardContent?

    var body: some View {
        if let item = monitor.selectedHistoryItem {
            VStack(spacing: 4) {
                // Header
                HStack {
                    if monitor.currentItemID == item.id {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Current")
                            .font(.caption)
                            .foregroundColor(.green)
                    }

                    Text(Utilities.formatDate(item.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let sourceApp = item.sourceApplication {
                        Spacer().frame(width: 8)

                        HStack {
                            if let nsImage = sourceApp.applicationIcon {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 16, height: 16)
                            }

                            if let appName = sourceApp.applicationName, !appName.isEmpty {
                                Text(appName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(4)
                        .contentShape(Rectangle())
                        .help(sourceApp.bundleIdentifier ?? "Unknown application")
                    }

                    Spacer()

                    Button(action: {
                        monitor.copyAllContentTypes(item)
                    }) {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .help("Copy to Clipboard")
                }
                .padding([.horizontal, .top], 4)

                // Content groups as tabs
                if !item.contents.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 2) {
                            ForEach(item.contents) { content in
                                Button(action: {
                                    selectContent(content)
                                }) {
                                    HStack(spacing: 2) {
                                        contentTypeIcon(for: content)
                                            .font(.caption)

                                        Text(getContentTabLabel(content))
                                            .font(.caption)
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 8)
                                    .background(
                                        selectedContent?.id == content.id
                                            ? Color.accentColor.opacity(0.2) : Color.clear
                                    )
                                    .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 4)
                        }
                        .padding(.bottom, 4)
                    }

                    // Content view
                    if let selectedContent = selectedContent {
                        contentView(for: selectedContent)
                    } else {
                        Text("No content selected")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                } else {
                    Text("No content types available")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: monitor.selectedHistoryItem) { oldItem, newItem in
                updateSelectionForItem(newItem)
            }
            .onAppear {
                updateSelectionForItem(item)
            }
        } else {
            VStack {
                Image(systemName: "clipboard")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                    .padding(.bottom)

                Text("Select a clipboard item to view details")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    // MARK: - Selection Management

    /// Updates selection when the selected history item changes
    private func updateSelectionForItem(_ item: ClipboardHistoryItem?) {
        guard let item = item, !item.contents.isEmpty else {
            selectedContent = nil
            return
        }

        // If current content is in the new history item, keep it selected
        if let currentContent = selectedContent,
            item.contents.contains(where: { $0.id == currentContent.id })
        {
            // Content is still valid, keep it selected
        } else {
            // Default to text content if available, otherwise first content
            if let textContent = item.contents.first(where: { $0.canRenderAsText }) {
                selectContent(textContent)
            } else {
                selectContent(item.contents.first)
            }
        }
    }

    private func selectContent(_ content: ClipboardContent?) {
        selectedContent = content
    }

    @ViewBuilder
    private func contentTypeIcon(for content: ClipboardContent) -> some View {
        if content.canRenderAsText {
            Image(systemName: "doc.text")
                .foregroundColor(.blue)
        } else if content.canRenderAsImage {
            Image(systemName: "photo")
                .foregroundColor(.green)
        } else {
            Image(systemName: "doc.fill")
                .foregroundColor(.gray)
        }
    }

    @ViewBuilder
    private func contentView(for content: ClipboardContent) -> some View {
        VStack(spacing: 4) {
            // Preview section
            Group {
                if content.canRenderAsText {
                    // Use LazyTextView for text content instead of Text
                    // This handles massive text content much more efficiently
                    LazyTextView(content: content, isEditable: false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if content.canRenderAsImage, let nsImage = NSImage(data: content.data) {
                    PDFImageView(image: nsImage)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack {
                        Text("Binary data: \(content.data.count) bytes")
                            .foregroundColor(.secondary)
                            .padding()

                        // ASCII interpretation for small binary data
                        if content.data.count < 1024 {
                            Divider()

                            VStack(alignment: .leading) {
                                Text("ASCII Interpretation:")
                                    .font(.subheadline)
                                    .padding(.bottom, 4)

                                ScrollView {
                                    Text(asciiRepresentation(of: content.data))
                                        .font(.system(.body, design: .monospaced))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .background(Color(NSColor.textBackgroundColor).opacity(0.5))
            .cornerRadius(6)

            // Integrated metadata section
            VStack(alignment: .leading, spacing: 4) {
                // Source application section when available
                if let sourceApp = monitor.selectedHistoryItem?.sourceApplication,
                    sourceApp.applicationName != nil || sourceApp.bundleIdentifier != nil
                {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Source Application")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fontWeight(.semibold)

                            Spacer()
                        }

                        HStack(spacing: 12) {
                            if let icon = sourceApp.applicationIcon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 24, height: 24)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                if let appName = sourceApp.applicationName {
                                    Text(appName)
                                        .font(.caption)
                                }

                                if let bundleId = sourceApp.bundleIdentifier {
                                    Text(bundleId)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .textSelection(.enabled)
                                }
                            }

                            Spacer()
                        }
                    }
                    .padding(6)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(4)
                }

                HStack {
                    VStack(alignment: .leading) {
                        HStack(alignment: .top) {
                            Text(content.formats.count == 1 ? "Format:" : "Formats:")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(content.formats.map(\.uti).joined(separator: "\n"))
                                .font(.caption2)
                                .textSelection(.enabled)
                        }

                        HStack {
                            Text("Size:")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            if content.canRenderAsText, let textSize = content.getTextSize() {
                                Text(
                                    "\(content.data.count) bytes / ~\(Utilities.formatSize(textSize)) characters"
                                )
                                .font(.caption2)
                            } else {
                                Text("\(content.data.count) bytes")
                                    .font(.caption2)
                            }
                        }
                    }

                    Spacer()
                }
            }
            .padding(8)
            .background(Color(NSColor.textBackgroundColor).opacity(0.3))
            .cornerRadius(6)
        }
        .padding(8)
    }

    // Generate better, more specific tab labels for content
    private func getContentTabLabel(_ content: ClipboardContent) -> String {
        let names = content.formats.map(\.shortTypeName).reduce(into: [String]()) { result, name in
            if !result.contains(name) { result.append(name) }
        }
        let representation = names.joined(separator: "/")

        if content.canRenderAsImage { return representation }
        if content.canRenderAsText { return representation }
        return representation.isEmpty ? "Data" : representation
    }

    private func asciiRepresentation(of data: Data) -> String {
        var result = ""
        let bytes = [UInt8](data)

        for (index, byte) in bytes.enumerated() {
            // Add newline every 16 bytes
            if index % 16 == 0 && index > 0 {
                result += "\n"
            }

            // Add readable character or dot for non-printable
            if byte >= 32 && byte <= 126 {
                result += String(format: "%c", byte)
            } else {
                result += "."
            }

            // Add space between characters
            if index % 16 != 15 && index != bytes.count - 1 {
                result += " "
            }
        }

        return result
    }
}
