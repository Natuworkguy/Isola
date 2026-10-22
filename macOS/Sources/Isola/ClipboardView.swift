import SwiftUI

struct ClipboardView: View {
    @ObservedObject var monitor: ClipboardMonitor
    @EnvironmentObject var state: AppState
    @State private var copiedID: UUID?

    private var searching: Bool { state.keyboardFocus }
    private var query: String { state.clipboardQuery }

    private var shown: [ClipboardEntry] {
        let words = query.lowercased().split(separator: " ")
        guard !words.isEmpty else { return monitor.entries }
        return monitor.entries.filter { entry in
            let haystack = entry.searchText.lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
    }

    var body: some View {
        if monitor.entries.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "doc.on.clipboard").font(.system(size: 26))
                Text("Clipboard is empty").font(.system(size: 14, weight: .semibold))
                Text("Copy text, links, colours or images and they will show up here.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .foregroundStyle(.white.opacity(0.8))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                header
                if shown.isEmpty {
                    Text("Nothing matches \u{201C}\(query)\u{201D}")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 10) {
                            ForEach(shown) { entry in
                                ClipCard(
                                    entry: entry,
                                    image: monitor.image(entry),
                                    copied: copiedID == entry.id,
                                    copy: { copy(entry) },
                                    remove: { monitor.remove(entry) },
                                    reveal: monitor.imageURL(entry)
                                )
                            }
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 2)
                    }
                    // The strip takes whatever height the tab leaves, and the cards fill it.
                    .frame(maxHeight: .infinity)
                }
            }
            .onDisappear { endSearch() }
            .onReceive(NotificationCenter.default.publisher(for: .isolaSearchSubmit)) { _ in
                if let first = shown.first { copy(first) }
            }
            .onChange(of: state.keyboardFocus) { _, open in
                if !open { state.clipboardQuery = "" }
            }
        }
    }

    @ViewBuilder private var header: some View {
        HStack(spacing: 8) {
            if searching {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    // The field itself is drawn by SearchFieldView in its own window, laid exactly over this spot.
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(GeometryReader { proxy in
                            Color.clear
                                .onAppear { state.searchFieldRect = proxy.frame(in: .global) }
                                .onChange(of: proxy.frame(in: .global)) { _, frame in state.searchFieldRect = frame }
                        })
                    Button { endSearch() } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Capsule().fill(Color.white.opacity(0.12)))
            } else {
                Text(monitor.entries.count == 1 ? "1 item" : "\(monitor.entries.count) items")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Button { startSearch() } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func copy(_ entry: ClipboardEntry) {
        monitor.copy(entry)
        copiedID = entry.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copiedID == entry.id { copiedID = nil }
        }
    }

    private func startSearch() {
        state.keyboardFocus = true
    }

    private func endSearch() {
        state.keyboardFocus = false
        state.clipboardQuery = ""
    }
}

extension Notification.Name {
    static let isolaSearchSubmit = Notification.Name("IsolaSearchSubmit")
}

/// The clipboard search field, alone in a small window over the search bar so that it, not the island, takes the
/// keyboard. Transparent, so it reads as part of the island.
struct SearchFieldView: View {
    @EnvironmentObject var state: AppState
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Search your clipboard", text: $state.clipboardQuery)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.white)
            .focused($focused)
            .onSubmit { NotificationCenter.default.post(name: .isolaSearchSubmit, object: nil) }
            .onExitCommand { state.keyboardFocus = false }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.colorScheme, .dark)
            .onChange(of: state.keyboardFocus, initial: true) { _, open in
                // After the window has become key, or the focus does not take.
                DispatchQueue.main.async { focused = open }
            }
    }
}

/// One clip: a text snippet, a link, a colour swatch or an image. Clicking it copies it again.
struct ClipCard: View {
    let entry: ClipboardEntry
    let image: NSImage?
    let copied: Bool
    let copy: () -> Void
    let remove: () -> Void
    let reveal: URL?
    @State private var hovering = false

    private static let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    var body: some View {
        Button(action: copy) {
            VStack(spacing: 0) {
                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                footer
            }
            .frame(width: 132)
            .frame(maxHeight: .infinity)
            .background(Self.shape.fill(Color.white.opacity(0.08)))
            .clipShape(Self.shape)
            .overlay(Self.shape.strokeBorder(Color.white.opacity(hovering ? 0.35 : 0.1), lineWidth: 1))
            .overlay {
                if copied {
                    ZStack {
                        Self.shape.fill(Color.black.opacity(0.55))
                        Label("Copied", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.green)
                    }
                    .transition(.opacity)
                }
            }
            .contentShape(Self.shape)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if hovering && !copied {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.white, Color.black.opacity(0.6))
                }
                .buttonStyle(.plain)
                .padding(5)
            }
        }
        .scaleEffect(hovering ? 1.03 : 1)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.easeOut(duration: 0.15), value: copied)
        .contextMenu {
            Button("Copy", action: copy)
            if entry.kind == .link, let url = URL(string: entry.text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                Button("Open Link") { NSWorkspace.shared.open(url) }
            }
            if let reveal {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([reveal]) }
            }
            Divider()
            Button("Delete", action: remove)
        }
    }

    @ViewBuilder private var preview: some View {
        switch entry.kind {
        case .text:
            Text(entry.text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(10)
        case .link:
            let url = URL(string: entry.text.trimmingCharacters(in: .whitespacesAndNewlines))
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "globe")
                    .font(.system(size: 18))
                    .foregroundStyle(.cyan)
                Text(url?.host ?? entry.text)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(url?.path ?? "")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(10)
        case .color:
            let rgb = ClipboardMonitor.rgb(entry.text)
            let light = rgb.map { 0.299 * $0.red + 0.587 * $0.green + 0.114 * $0.blue > 0.6 } ?? false
            ZStack {
                if let rgb {
                    Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
                } else {
                    Color.gray
                }
                Text(entry.text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(light ? Color.black : Color.white)
            }
        case .image:
            if let image {
                Color.clear.overlay {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                }
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 24))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
            Text(label)
                .font(.system(size: 10, weight: .semibold))
            Spacer(minLength: 0)
            if entry.kind == .image, let size = entry.pixelSize {
                Text(size)
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .foregroundStyle(.white.opacity(0.8))
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Color.black.opacity(0.3))
    }

    private var symbol: String {
        switch entry.kind {
        case .text: return "text.alignleft"
        case .link: return "link"
        case .color: return "paintpalette.fill"
        case .image: return "photo"
        }
    }

    private var label: String {
        switch entry.kind {
        case .text: return "Text"
        case .link: return "Link"
        case .color: return "Colour"
        case .image: return "Image"
        }
    }
}
