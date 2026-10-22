import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A drop target that appears at the pointer when a file being dragged is shaken, so files can be dropped without
/// dragging all the way up to the island.
final class Basket: ObservableObject {
    enum Target: String, CaseIterable, Identifiable {
        case tray, airDrop, convert, zip

        var id: String { rawValue }

        var title: String {
            switch self {
            case .tray: return "Tray"
            case .airDrop: return "AirDrop"
            case .convert: return "Convert"
            case .zip: return "Zip"
            }
        }

        var symbol: String {
            switch self {
            case .tray: return "tray.and.arrow.down.fill"
            case .airDrop: return "dot.radiowaves.left.and.right"
            case .convert: return "arrow.triangle.2.circlepath"
            case .zip: return "archivebox.fill"
            }
        }
    }

    /// The window: the 202pt panel plus 35pt on every side for its shadow, so the window edge never cuts it off.
    static let size = CGSize(width: 272, height: 272)

    @Published private(set) var visible = false
    @Published var targeted: Target?

    private var panel: NotchPanel?
    private var hideWork: DispatchWorkItem?

    func show(at point: NSPoint) {
        hideWork?.cancel()
        let panel = self.panel ?? makePanel()
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        var origin = NSPoint(x: point.x - Self.size.width / 2, y: point.y - Self.size.height / 2)
        if let frame = screen?.visibleFrame {
            origin.x = min(max(origin.x, frame.minX + 8), frame.maxX - Self.size.width - 8)
            origin.y = min(max(origin.y, frame.minY + 8), frame.maxY - Self.size.height - 8)
        }
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) { visible = true }
        if UserDefaults.standard.bool(forKey: Prefs.haptics) {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
    }

    func hide() {
        hideWork?.cancel()
        withAnimation(.easeIn(duration: 0.18)) { visible = false }
        targeted = nil
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.visible else { return }
            self.panel?.orderOut(nil)
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    /// The drag ended: dropped on a target or not, the Basket goes away.
    func dragEnded() {
        guard visible else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.hide() }
    }

    func drop(_ providers: [NSItemProvider], on target: Target) -> Bool {
        let accepted = FileActions.loadFileURLs(providers) { urls in
            guard !urls.isEmpty else { return }
            Self.perform(target, urls)
        }
        hide()
        return accepted
    }

    private static func perform(_ target: Target, _ urls: [URL]) {
        let state = AppState.shared
        let count = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files"
        switch target {
        case .tray:
            state.tray.add(urls)
            state.showBanner(IslandBanner(symbol: "tray.and.arrow.down.fill", tint: .blue,
                                          title: "Added to the tray", subtitle: count), for: 3)
        case .airDrop:
            FileActions.airDrop(urls)
        case .convert:
            guard urls.contains(where: FileActions.isImage) else {
                state.showBanner(IslandBanner(symbol: "photo.badge.exclamationmark", tint: .orange,
                                              title: "Nothing to convert", subtitle: "Only images can be converted"),
                                 for: 3)
                return
            }
            FileActions.convertImages(urls) { made in
                guard !made.isEmpty else {
                    state.showBanner(IslandBanner(symbol: "photo.badge.exclamationmark", tint: .orange,
                                                  title: "Could not convert \(count)",
                                                  subtitle: "macOS could not read the image"), for: 4)
                    return
                }
                state.tray.add(made)
                state.showBanner(IslandBanner(
                    symbol: "arrow.triangle.2.circlepath", tint: .purple,
                    title: made.count == 1 ? "Converted \(made[0].lastPathComponent)" : "Converted \(made.count) images",
                    subtitle: "Saved to Downloads and added to the tray"), for: 4)
            }
        case .zip:
            FileActions.zip(urls) { archive in
                guard let archive else { return }
                NSWorkspace.shared.activateFileViewerSelecting([archive])
                state.showBanner(IslandBanner(symbol: "archivebox.fill", tint: .brown,
                                              title: "Zipped \(count)", subtitle: archive.lastPathComponent), for: 4)
            }
        }
    }

    private func makePanel() -> NotchPanel {
        let panel = NotchPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: BasketView(basket: self))
        self.panel = panel
        return panel
    }
}

struct BasketView: View {
    @ObservedObject var basket: Basket

    private static let shape = UnevenRoundedRectangle(
        topLeadingRadius: 26, bottomLeadingRadius: 26, bottomTrailingRadius: 26, topTrailingRadius: 26,
        style: .continuous)

    var body: some View {
        LazyVGrid(columns: [GridItem(.fixed(84), spacing: 10), GridItem(.fixed(84), spacing: 10)], spacing: 10) {
            ForEach(Basket.Target.allCases) { target in
                tile(target)
            }
        }
        // A lazy grid takes all the width it is offered; hold it to its two columns so the panel hugs the tiles.
        .frame(width: 84 * 2 + 10)
        .padding(12)
        .background {
            // The island's own blur, clipped to the shape. SwiftUI's materials drew a grey rectangle in this
            // transparent window, and a plain shadow showed through the translucent panel.
            ZStack {
                VisualEffectBlur()
                Color.black.opacity(0.35)
            }
            .clipShape(Self.shape)
            .overlay(Self.shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            .background(
                Self.shape.fill(Color.black)
                    .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                    .clipShape(OutsideShape(inner: Self.shape), style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)
            )
        }
        .scaleEffect(basket.visible ? 1 : 0.6)
        .opacity(basket.visible ? 1 : 0)
        .frame(width: Basket.size.width, height: Basket.size.height)
    }

    private func tile(_ target: Basket.Target) -> some View {
        let lit = basket.targeted == target
        return VStack(spacing: 6) {
            Image(systemName: target.symbol)
                .font(.system(size: 20, weight: .semibold))
            Text(target.title)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(lit ? Color.black : Color.white)
        .frame(width: 84, height: 84)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(lit ? Color.white : Color.white.opacity(0.1))
        )
        .scaleEffect(lit ? 1.06 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: lit)
        .onDrop(of: [.fileURL], isTargeted: Binding(
            get: { basket.targeted == target },
            set: { inside in
                if inside {
                    basket.targeted = target
                } else if basket.targeted == target {
                    basket.targeted = nil
                }
            }
        )) { providers in
            basket.drop(providers, on: target)
        }
    }
}
