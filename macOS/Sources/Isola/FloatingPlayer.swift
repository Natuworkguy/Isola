import AppKit
import SwiftUI

/// The music in a small window of its own, anywhere on the desktop and on every Space. Drag it by any part that isn't a
/// control; it remembers where it was, and whether it was open, across launches.
final class FloatingPlayer: ObservableObject {
    static let shared = FloatingPlayer()

    @Published private(set) var isShown = false

    private var panel: NSPanel?
    private var dragFrom: (mouse: NSPoint, origin: NSPoint)?
    private static let frameName = "IsolaFloatingPlayer"
    private static let size = NSSize(width: 330, height: 104)

    /// Opens it again at launch if it was open when Isola quit.
    func restore() {
        if UserDefaults.standard.bool(forKey: Prefs.floatingPlayer) { show() }
    }

    func toggle() { isShown ? hide() : show() }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) { place(panel) }
        panel.orderFrontRegardless()
        isShown = true
        UserDefaults.standard.set(true, forKey: Prefs.floatingPlayer)
    }

    func hide() {
        panel?.orderOut(nil)
        isShown = false
        UserDefaults.standard.set(false, forKey: Prefs.floatingPlayer)
    }

    /// Moves the window with the pointer while a drag lasts.
    func drag(ended: Bool) {
        guard let panel, !ended else {
            dragFrom = nil
            return
        }
        let mouse = NSEvent.mouseLocation
        let from = dragFrom ?? (mouse: mouse, origin: panel.frame.origin)
        dragFrom = from
        panel.setFrameOrigin(NSPoint(x: from.origin.x + mouse.x - from.mouse.x, y: from.origin.y + mouse.y - from.mouse.y))
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        let view = FloatingPlayerView(monitor: AppState.shared.nowPlaying, player: self)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: Self.size)
        panel.contentView = host
        place(panel)
        // Puts it back where it was last time, if there was a last time.
        panel.setFrameAutosaveName(Self.frameName)
        return panel
    }

    /// The bottom right corner of the main screen.
    private func place(_ panel: NSPanel) {
        guard let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: screen.maxX - Self.size.width - 20, y: screen.minY + 20))
    }
}

struct FloatingPlayerView: View {
    @ObservedObject var monitor: NowPlayingMonitor
    let player: FloatingPlayer
    @State private var scrubFraction: Double?
    @State private var hovering = false

    var body: some View {
        content
            .padding(12)
            .frame(width: 330, height: 104)
            .background(VisualEffectBlur())
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.1)))
            .overlay(alignment: .topTrailing) { closeButton }
            .foregroundStyle(.white)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { _ in player.drag(ended: false) }
                    .onEnded { _ in player.drag(ended: true) }
            )
            .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { hovering = inside } }
    }

    @ViewBuilder private var content: some View {
        if monitor.hasTrack {
            HStack(spacing: 12) {
                ArtworkView(image: monitor.artwork, icon: monitor.sourceIcon, size: 80, radius: 14)
                    .shadow(color: monitor.tint.opacity(0.5), radius: 10, y: 3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(monitor.title)
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)
                    Text(monitor.artist)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    scrubber
                        .disabled(monitor.isBackground)
                    HStack(spacing: 22) {
                        control("backward.fill", 13, monitor.previous)
                        control(monitor.isPlaying ? "pause.fill" : "play.fill", 19, monitor.togglePlayPause)
                        control("forward.fill", 13, monitor.next)
                    }
                    // A background player cannot be reached by the Mac's media commands.
                    .disabled(monitor.isBackground)
                    .opacity(monitor.isBackground ? 0.35 : 1)
                    .frame(maxWidth: .infinity)
                }
                .padding(.trailing, 14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 10) {
                Image(systemName: "music.note.list").font(.system(size: 22))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nothing playing").font(.system(size: 13, weight: .semibold))
                    Text("Play music or a video in any app.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .foregroundStyle(.white.opacity(0.8))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var closeButton: some View {
        Button { player.hide() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.white.opacity(0.18)))
        }
        .buttonStyle(.plain)
        .padding(8)
        .opacity(hovering ? 1 : 0)
        .help("Close the floating player")
    }

    private var fraction: Double {
        if let scrubFraction { return scrubFraction }
        return monitor.duration > 0 ? min(max(monitor.position / monitor.duration, 0), 1) : 0
    }

    private var scrubber: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule().fill(Color.white).frame(width: max(width * fraction, 0))
            }
            .frame(height: scrubFraction == nil ? 4 : 6)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard monitor.duration > 0 else { return }
                        scrubFraction = min(max(value.location.x / max(width, 1), 0), 1)
                    }
                    .onEnded { value in
                        if monitor.duration > 0 {
                            monitor.seek(to: min(max(value.location.x / max(width, 1), 0), 1) * monitor.duration)
                        }
                        scrubFraction = nil
                    }
            )
            .animation(.easeOut(duration: 0.15), value: scrubFraction == nil)
        }
        .frame(height: 12)
    }

    private func control(_ symbol: String, _ size: CGFloat, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .frame(width: 28, height: 22)
                .contentTransition(.symbolEffect(.replace))
                .animation(.snappy(duration: 0.25), value: symbol)
        }
        .buttonStyle(.plain)
    }
}
