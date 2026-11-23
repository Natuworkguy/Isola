import AppKit
import ApplicationServices
import SwiftUI

/// Getting a permission the easy way: System Settings opens at the right list, and a small card sits beside its
/// window with Isola's icon on it. Drag the icon into the list, turn its switch on, and the card ticks itself off and
/// goes. The card follows the Settings window if it moves, and closes if Settings does.
enum PermissionHelper {
    enum Kind {
        case accessibility, screenRecording

        var pane: String {
            switch self {
            case .accessibility: return "Privacy_Accessibility"
            case .screenRecording: return "Privacy_ScreenCapture"
            }
        }

        var title: String {
            switch self {
            case .accessibility: return "Accessibility"
            case .screenRecording: return "Screen & System Audio Recording"
            }
        }

        var granted: Bool {
            switch self {
            case .accessibility: return AXIsProcessTrusted()
            case .screenRecording: return CGPreflightScreenCaptureAccess()
            }
        }
    }

    private static var panel: NSPanel?
    private static var timer: Timer?
    private static var model: HelperModel?
    private static var sawSettings = false

    /// Opens System Settings at the list for KIND and puts the card beside it.
    static func show(_ kind: Kind) {
        if kind.granted { return }
        // asked once the usual way too, so Isola is already in the list where macOS can put it there
        switch kind {
        case .accessibility:
            let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([prompt: false] as CFDictionary)
        case .screenRecording:
            _ = CGRequestScreenCaptureAccess()
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(kind.pane)") {
            NSWorkspace.shared.open(url)
        }
        close()
        let m = HelperModel(kind: kind)
        model = m
        let made = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 132),
                           styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        made.isFloatingPanel = true
        made.level = .floating
        made.hasShadow = true
        made.isOpaque = false
        made.backgroundColor = .clear
        made.hidesOnDeactivate = false
        made.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        made.isMovableByWindowBackground = true
        made.contentView = NSHostingView(rootView: HelperCard(model: m, close: close))
        panel = made
        sawSettings = false
        place()
        made.orderFrontRegardless()
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in tick() }
    }

    static func close() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
        model = nil
    }

    private static func tick() {
        guard let m = model else { return close() }
        if !m.done && m.kind.granted {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { m.done = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { close() }
            return
        }
        // Settings closed after it had opened: nothing to drag into any more
        if settingsFrame() == nil {
            if sawSettings { close() }
            return
        }
        sawSettings = true
        place()
    }

    /// Beside the Settings window, at its lower right where the list ends; under the pointer's screen otherwise.
    private static func place() {
        guard let panel else { return }
        let size = panel.frame.size
        if let f = settingsFrame() {
            var origin = NSPoint(x: f.maxX + 12, y: f.minY + 24)
            let screen = NSScreen.screens.first { $0.frame.intersects(f) } ?? NSScreen.main
            if let vis = screen?.visibleFrame, origin.x + size.width > vis.maxX {
                // no room to the right: over the window's lower right corner instead
                origin = NSPoint(x: f.maxX - size.width - 16, y: f.minY + 16)
            }
            panel.setFrameOrigin(origin)
        } else if let vis = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: vis.maxX - size.width - 24, y: vis.minY + 24))
        }
    }

    /// System Settings' window, in AppKit's coordinates (from the bottom of the main screen).
    private static func settingsFrame() -> NSRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return nil }
        for w in list {
            let owner = w[kCGWindowOwnerName as String] as? String ?? ""
            let layer = w[kCGWindowLayer as String] as? Int ?? 1
            guard layer == 0, owner == "System Settings" || owner == "System Preferences",
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let wd = b["Width"], let h = b["Height"], wd > 200 else { continue }
            let top = NSScreen.screens.first?.frame.maxY ?? 0
            return NSRect(x: x, y: top - y - h, width: wd, height: h)
        }
        return nil
    }
}

final class HelperModel: ObservableObject {
    let kind: PermissionHelper.Kind
    @Published var done = false

    init(kind: PermissionHelper.Kind) { self.kind = kind }
}

/// The card: Isola's icon to drag, and what to do with it.
private struct HelperCard: View {
    @ObservedObject var model: HelperModel
    let close: () -> Void
    @State private var nudge = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                if model.done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40, weight: .semibold)).foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable().frame(width: 58, height: 58)
                        .offset(x: nudge ? -5 : 0, y: nudge ? -3 : 0)
                        .onDrag { NSItemProvider(object: Bundle.main.bundleURL as NSURL) }
                        .help("Drag into the list")
                }
            }
            .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.done ? "Allowed" : "Drag Isola into the list")
                    .font(.system(size: 14, weight: .bold))
                Text(model.done ? "\(model.kind.title) is on for Isola."
                     : "Under \(model.kind.title), then turn its switch on. If Isola is there already, just turn it on.")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if model.kind == .screenRecording && !model.done {
                    Text("macOS may ask to reopen Isola after.")
                        .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 320, height: 132)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1)))
        .overlay(alignment: .topTrailing) {
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(.quaternary))
            }
            .buttonStyle(.plain)
            .padding(8)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { nudge = true }
        }
    }
}
