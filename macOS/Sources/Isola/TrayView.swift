import SwiftUI
import UniformTypeIdentifiers

struct TrayView: View {
    @ObservedObject var tray: FileTray
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .foregroundStyle(state.isDropTargeted ? Color.accentColor : Color.white.opacity(0.25))

                if tray.items.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "arrow.down.doc").font(.system(size: 26))
                        Text("Drop files here").font(.system(size: 14, weight: .semibold))
                        Text("Drag them back out whenever you need them.")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .foregroundStyle(.white.opacity(0.8))
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(tray.items) { item in
                                TrayTile(item: item, tray: tray)
                            }
                        }
                        .padding(12)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .onDrop(of: [.fileURL], isTargeted: $state.isDropTargeted) { providers in
                tray.handleDrop(providers)
            }

            HStack {
                if let message = tray.statusMessage {
                    Text(message).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                if !tray.items.isEmpty {
                    pill("AirDrop", "dot.radiowaves.left.and.right") { FileActions.airDrop(tray.items.map(\.url)) }
                    ShareLink(items: tray.items.map(\.url)) {
                        pillLabel("Share", "square.and.arrow.up")
                    }
                    .buttonStyle(.plain)
                    pill("Zip all", "archivebox") { tray.zipAll() }
                    pill("Clear", "xmark") { tray.clear() }
                }
            }
            .frame(height: 22)
        }
    }

    private func pill(_ title: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { pillLabel(title, symbol) }
            .buttonStyle(.plain)
    }

    private func pillLabel(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.14)))
    }
}

struct TrayTile: View {
    let item: TrayItem
    @ObservedObject var tray: FileTray
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: item.icon).resizable().frame(width: 52, height: 52)
            Text(item.name)
                .font(.system(size: 10))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 70)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(hovering ? 0.14 : 0.07)))
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button { tray.remove(item) } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 15))
                        .foregroundStyle(.white, .gray)
                }
                .buttonStyle(.plain)
                .offset(x: 5, y: -5)
            }
        }
        .onHover { hovering = $0 }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .contextMenu {
            Button("AirDrop") { FileActions.airDrop([item.url]) }
            ShareLink(item: item.url)
            if FileActions.isImage(item.url) {
                let format = FileActions.conversionTarget(for: item.url) == .png ? "PNG" : "JPEG"
                Button("Convert to \(format)") { tray.convert(item) }
            }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            Divider()
            Button("Remove from Tray") { tray.remove(item) }
        }
    }
}
