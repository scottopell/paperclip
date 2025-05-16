import AppKit
import Combine
import SwiftUI

struct QuickSearchView: View {
    @ObservedObject var monitor: ClipboardMonitor
    @State private var searchText: String = ""
    @State private var debouncedSearchText: String = ""
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isSearchFieldFocused: Bool

    // Add a timer publisher for debouncing
    private let searchTextPublisher = PassthroughSubject<String, Never>()
    @State private var cancellable: AnyCancellable?

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Search clipboard history...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18))
                    .focused($isSearchFieldFocused)
                    .onChange(of: searchText) { newValue in
                        searchTextPublisher.send(newValue)
                    }

                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        searchTextPublisher.send("")
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        colorScheme == .dark
                            ? Color(NSColor.controlBackgroundColor)
                            : Color(NSColor.textBackgroundColor))
            )
            .padding([.horizontal, .top], 16)

            // History list
            HistoryListView(
                monitor: monitor, showSearchBar: false, externalSearchText: debouncedSearchText
            )
            .padding([.horizontal, .bottom], 16)
            .padding(.top, 8)
        }
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .edgesIgnoringSafeArea(.all)
        )
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            // Set focus to search field
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFieldFocused = true
            }

            // Setup the debounced search
            cancellable =
                searchTextPublisher
                .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
                .sink { value in
                    debouncedSearchText = value
                }
        }
        .onKeyPress(.escape) {
            QuickSearchManager.shared.hideQuickSearch()
            return .handled
        }
    }
}

// Helper view to create NSVisualEffectView in SwiftUI
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
