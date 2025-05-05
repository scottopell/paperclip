//
//  ClipboardDetailView.swift
//  spaperclip
//
//  Created by Scott Opell on 5/4/25.
//

import SwiftUI

struct ClipboardDetailView: View {
    @ObservedObject var monitor: ClipboardMonitor
    let item: ClipboardHistoryItem?

    var body: some View {
        if let item = item {
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

                    Text(formatDate(item.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button(action: {
                        copyAllContentTypes(item)
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
                                    monitor.selectContent(content)
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
                                        monitor.selectedContent?.id == content.id
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

                    // Format picker - only show if the selected content has multiple formats
                    if let selectedContent = monitor.selectedContent,
                        selectedContent.formats.count > 1
                    {
                        HStack {
                            Text("Format:")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Picker(
                                "",
                                selection: Binding<ClipboardFormat?>(
                                    get: { monitor.selectedFormat },
                                    set: { monitor.selectFormat($0) }
                                )
                            ) {
                                ForEach(selectedContent.formats) { format in
                                    Text(format.typeName).tag(format as ClipboardFormat?)
                                }
                            }
                            .pickerStyle(.menu)

                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 4)
                    }

                    // Content view
                    if let selectedContent = monitor.selectedContent,
                        let selectedFormat = monitor.selectedFormat
                    {
                        contentView(for: selectedContent, selectedFormat: selectedFormat)
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
            .onAppear {
                // Set the monitor's selected history item when the view appears
                monitor.selectHistoryItem(item)
            }
            .onChange(of: item) { oldItem, newItem in
                if monitor.selectedHistoryItem?.id != newItem.id {
                    monitor.selectHistoryItem(newItem)
                }
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

    @ViewBuilder
    private func contentTypeIcon(for content: ClipboardContent) -> some View {
        if content.canRenderAsText {
            Image(systemName: "doc.text")
                .foregroundColor(.blue)
        } else if content.canRenderAsImage {
            Image(systemName: "photo")
                .foregroundColor(.green)
        } else {
            Image(systemName: "doc.binary")
                .foregroundColor(.gray)
        }
    }

    @ViewBuilder
    private func contentView(for content: ClipboardContent, selectedFormat: ClipboardFormat)
        -> some View
    {
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
                HStack {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("UTI:")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(selectedFormat.uti)
                                .font(.caption2)
                                .textSelection(.enabled)
                        }

                        HStack {
                            Text("Size:")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            if content.canRenderAsText, let textSize = content.getTextSize() {
                                Text(
                                    "\(content.data.count) bytes / ~\(formatSizeWithUnits(textSize)) characters"
                                )
                                .font(.caption2)
                            } else {
                                Text("\(content.data.count) bytes")
                                    .font(.caption2)
                            }
                        }
                    }

                    Spacer()

                    // Show alternative formats as buttons
                    if content.formats.count > 1 {
                        VStack(alignment: .trailing) {
                            Text("Other formats:")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            HStack {
                                ForEach(content.formats.filter { $0.id != selectedFormat.id }) {
                                    format in
                                    Button(format.typeName) {
                                        monitor.selectFormat(format)
                                    }
                                    .font(.caption2)
                                    .buttonStyle(.link)
                                }
                            }
                        }
                    }
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
        if content.formats.count == 1 {
            return content.formats[0].typeName
        }

        // Create more specific labels for content with multiple formats
        if content.canRenderAsText {
            // For text types, include the specific formats
            let formatNames = content.formats.prefix(2).map {
                $0.typeName.replacingOccurrences(of: " Text", with: "")
            }
            let additionalCount = content.formats.count > 2 ? " +\(content.formats.count - 2)" : ""
            return "Text (\(formatNames.joined(separator: "/"))\(additionalCount))"
        } else if content.canRenderAsImage {
            // For image types, include the specific formats
            let formatNames = content.formats.prefix(2).map {
                $0.typeName.replacingOccurrences(of: " Image", with: "")
            }
            let additionalCount = content.formats.count > 2 ? " +\(content.formats.count - 2)" : ""
            return "Image (\(formatNames.joined(separator: "/"))\(additionalCount))"
        } else {
            // For other types, show data size
            return "Data (\(content.data.count) bytes)"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
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

    private func formatSizeWithUnits(_ size: Int) -> String {
        if size < 1_000 {
            return "\(size)"
        } else if size < 1_000_000 {
            return String(format: "%.1fK", Double(size) / 1_000)
        } else {
            return String(format: "%.1fM", Double(size) / 1_000_000)
        }
    }

    private func copyAllContentTypes(_ item: ClipboardHistoryItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        for content in item.contents {
            for format in content.formats {
                pasteboard.setData(content.data, forType: NSPasteboard.PasteboardType(format.uti))
            }
        }
    }
}
