import AppKit
import SwiftUI

/// The Ring: a circle of Isola's tools around the pointer (⌃⌥Space). Click one, or press its number; Escape or a
/// click anywhere else puts it away.
final class RingMenu {
    static let shared = RingMenu()

    struct Item: Identifiable {
        let id: Int
        let title: String
        let symbol: String
        let tint: Color
        let perform: () -> Void
    }

    private var panel: NSPanel?
    private var monitors: [Any] = []
    /// The app that was in front, for window snapping to act on it rather than on Isola.
    private var frontApp: NSRunningApplication?

    lazy var items: [Item] = [
        Item(id: 1, title: "Capture", symbol: "camera.viewfinder", tint: .blue) { Capture.markup() },
        Item(id: 2, title: "Copy Text", symbol: "text.viewfinder", tint: .teal) { Capture.text() },
        Item(id: 3, title: "Dictate", symbol: "waveform", tint: .pink) { Dictation.shared.toggle() },
        Item(id: 4, title: "Colour", symbol: "eyedropper", tint: .orange) { RingMenu.pickColour() },
        Item(id: 5, title: "File Tray", symbol: "tray.full.fill", tint: .indigo) { RingMenu.openIsland(.tray) },
        Item(id: 6, title: "Clipboard", symbol: "doc.on.clipboard.fill", tint: .mint) { RingMenu.openIsland(.clipboard) },
        Item(id: 7, title: "Left Half", symbol: "rectangle.lefthalf.filled", tint: .purple) { [weak self] in self?.snap(.left) },
        Item(id: 8, title: "Right Half", symbol: "rectangle.righthalf.filled", tint: .purple) { [weak self] in self?.snap(.right) },
    ]

    func toggle() {
        panel == nil ? show() : hide()
    }

    private func show() {
        frontApp = NSWorkspace.shared.frontmostApplication
        let size: CGFloat = 300
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        var origin = CGPoint(x: mouse.x - size / 2, y: mouse.y - size / 2)
        if let frame = screen?.visibleFrame {
            origin.x = min(max(origin.x, frame.minX), frame.maxX - size)
            origin.y = min(max(origin.y, frame.minY), frame.maxY - size)
        }
        let panel = KeyPanel(contentRect: CGRect(origin: origin, size: CGSize(width: size, height: size)),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: RingView(items: items) { [weak self] item in self?.choose(item) })
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel

        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { self.hide(); return nil }  // Escape
            if let digit = Int(event.charactersIgnoringModifiers ?? ""), let item = self.items.first(where: { $0.id == digit }) {
                self.choose(item)
                return nil
            }
            return event
        } as Any)
    }

    private func hide() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        panel?.orderOut(nil)
        panel = nil
    }

    private func choose(_ item: Item) {
        hide()
        // the ring gone before a capture starts, so it isn't in the picture
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { item.perform() }
    }

    private func snap(_ spot: WindowSnap.Spot) {
        frontApp?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { WindowSnap.snap(spot) }
    }

    static func openIsland(_ tab: IslandTab) {
        let state = AppState.shared
        state.tab = tab
        state.heldOpen = true
        state.isExpanded = true
    }

    /// The colour under the pointer, picked with macOS's magnifier, copied as a hex code.
    static func pickColour() {
        NSColorSampler().show { picked in
            guard let rgb = picked?.usingColorSpace(.sRGB) else { return }
            let hex = String(format: "#%02X%02X%02X", Int(round(rgb.redComponent * 255)),
                             Int(round(rgb.greenComponent * 255)), Int(round(rgb.blueComponent * 255)))
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(hex, forType: .string)
            AppState.shared.showBanner(IslandBanner(symbol: "eyedropper", tint: Color(nsColor: rgb),
                                                    title: "Copied \(hex)", subtitle: ""), for: 2)
        }
    }
}

/// A borderless panel that can still take the keyboard, for Escape and the numbers.
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

struct RingView: View {
    let items: [RingMenu.Item]
    let choose: (RingMenu.Item) -> Void
    @State private var hovered: Int?
    @State private var shown = false

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                .frame(width: 270, height: 270)
                .shadow(color: .black.opacity(0.35), radius: 18, y: 6)
            VStack(spacing: 2) {
                Text(hovered.flatMap { id in items.first { $0.id == id }?.title } ?? "Isola")
                    .font(.system(size: 13, weight: .semibold))
                Text(hovered == nil ? "Pick a tool" : "Press \(hovered!)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 92)
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let angle = Double(index) / Double(items.count) * 2 * .pi - .pi / 2
                Button { choose(item) } label: {
                    ZStack {
                        Circle().fill(item.tint.gradient)
                            .frame(width: hovered == item.id ? 54 : 46, height: hovered == item.id ? 54 : 46)
                            .shadow(color: item.tint.opacity(0.5), radius: hovered == item.id ? 8 : 3)
                        Image(systemName: item.symbol)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? item.id : (hovered == item.id ? nil : hovered) }
                .offset(x: cos(angle) * (shown ? 98 : 30), y: sin(angle) * (shown ? 98 : 30))
                .opacity(shown ? 1 : 0)
                .animation(.spring(response: 0.32, dampingFraction: 0.72).delay(Double(index) * 0.015), value: shown)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovered)
            }
        }
        .frame(width: 300, height: 300)
        .onAppear { shown = true }
    }
}
