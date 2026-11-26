import AppKit
import SwiftUI

/// A remote for a Google TV or Android TV, over adb on the network: the arrows and OK, Back, Home, the volume,
/// power, typing into the TV's search boxes, and opening its apps. The TV has to have network debugging on and to
/// have allowed this Mac once (the same steps as installing Flash for TV).
final class TVRemote: ObservableObject {
    static let shared = TVRemote()

    enum State: Equatable { case unknown, noADB, connecting, ready, refused(String) }

    @Published private(set) var state: State = .unknown
    private let queue = DispatchQueue(label: "isola.tv-remote")
    private var serial = ""

    static let adbPaths = [
        "/opt/homebrew/bin/adb", "/usr/local/bin/adb",
        "/opt/homebrew/share/android-commandlinetools/platform-tools/adb",
        NSHomeDirectory() + "/Library/Android/sdk/platform-tools/adb",
    ]

    static var adb: String? { adbPaths.first { FileManager.default.isExecutableFile(atPath: $0) } }

    /// Connects to the chosen Cast TV's address (adb's port 5555).
    func connect() {
        guard let adb = Self.adb else { state = .noADB; return }
        state = .connecting
        TVs.shared.address { [weak self] host in
            guard let self else { return }
            guard let host else { self.state = .refused("Choose a Google TV in the TV widget first."); return }
            self.queue.async {
                let target = "\(host):5555"
                let out = Self.run(adb, ["connect", target])
                let devices = Self.run(adb, ["devices"])
                let line = devices.split(separator: "\n").first { $0.hasPrefix(target) } ?? ""
                let result: State
                if line.hasSuffix("device") {
                    result = .ready
                } else if line.hasSuffix("unauthorized") || out.contains("authenticate") {
                    result = .refused("Allow this Mac on the TV: the box says \"Allow USB debugging?\".")
                } else {
                    result = .refused("The TV didn't answer. Turn on network debugging in its Developer options.")
                }
                DispatchQueue.main.async {
                    self.serial = target
                    self.state = result
                }
            }
        }
    }

    // MARK: Keys

    func key(_ code: String) { shell(["input", "keyevent", code]) }

    /// Text into whatever box has the focus on the TV.
    func type(_ text: String) {
        guard !text.isEmpty else { return }
        // input text takes %s for a space; the shell's own characters are quoted
        let escaped = text.replacingOccurrences(of: " ", with: "%s")
            .replacingOccurrences(of: "'", with: "'\\''")
        shell(["input", "text", "'\(escaped)'"])
    }

    func open(_ package: String) {
        shell(["monkey", "-p", package, "-c", "android.intent.category.LEANBACK_LAUNCHER", "1"])
    }

    private func shell(_ args: [String]) {
        guard let adb = Self.adb, !serial.isEmpty, state == .ready else {
            if state != .connecting { connect() }
            return
        }
        let s = serial
        queue.async {
            let out = Self.run(adb, ["-s", s, "shell"] + args)
            if out.contains("not found") || out.contains("offline") || out.contains("unauthorized") {
                DispatchQueue.main.async { self.state = .unknown; self.connect() }
            }
        }
    }

    @discardableResult
    private static func run(_ adb: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: adb)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    struct App: Identifiable {
        let name: String
        let package: String
        let symbol: String
        var id: String { package }
    }

    static let apps: [App] = [
        App(name: "YouTube", package: "com.google.android.youtube.tv", symbol: "play.rectangle.fill"),
        App(name: "Netflix", package: "com.netflix.ninja", symbol: "film.fill"),
        App(name: "Prime Video", package: "com.amazon.amazonvideo.livingroom", symbol: "play.tv.fill"),
        App(name: "Disney+", package: "com.disney.disneyplus", symbol: "sparkles.tv.fill"),
        App(name: "Max", package: "com.wbd.stream", symbol: "tv.inset.filled"),
        App(name: "Spotify", package: "com.spotify.tv.android", symbol: "music.note"),
        App(name: "Plex", package: "com.plexapp.android", symbol: "server.rack"),
        App(name: "Flash", package: "dev.flashproject.tv", symbol: "bolt.fill"),
    ]
}

/// The remote, in a small window of its own that floats over everything.
final class TVRemoteWindow {
    static let shared = TVRemoteWindow()
    private var panel: NSPanel?

    func show() {
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 520),
                            styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView, .utilityWindow],
                            backing: .buffered, defer: false)
            p.title = "TV Remote"
            p.titlebarAppearsTransparent = true
            p.isFloatingPanel = true
            p.level = .floating
            p.hidesOnDeactivate = false
            p.isReleasedWhenClosed = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.contentView = NSHostingView(rootView: TVRemoteView(remote: .shared, tvs: .shared))
            if let screen = NSScreen.main?.visibleFrame {
                p.setFrameOrigin(NSPoint(x: screen.maxX - 290, y: screen.midY - 260))
            }
            panel = p
        }
        panel?.orderFrontRegardless()
        panel?.makeKey()
        if TVRemote.shared.state != .ready { TVRemote.shared.connect() }
    }
}

struct TVRemoteView: View {
    @ObservedObject var remote: TVRemote
    @ObservedObject var tvs: TVs
    @State private var text = ""

    var body: some View {
        VStack(spacing: 12) {
            Text(tvs.chosen?.name ?? "No TV chosen")
                .font(.system(size: 13, weight: .semibold))
                .padding(.top, 22)
            switch remote.state {
            case .noADB:
                message("Install adb to use the remote:", detail: "brew install android-platform-tools")
            case .refused(let why):
                message(why, detail: nil)
                Button("Try again") { remote.connect() }.controlSize(.small)
            case .connecting, .unknown:
                ProgressView().controlSize(.small)
            case .ready:
                EmptyView()
            }
            HStack(spacing: 18) {
                pad("power", "KEYCODE_POWER", tint: .red)
                pad("house.fill", "KEYCODE_HOME")
                pad("chevron.backward", "KEYCODE_BACK")
            }
            dpad
            HStack(spacing: 18) {
                pad("backward.fill", "KEYCODE_MEDIA_REWIND")
                pad("playpause.fill", "KEYCODE_MEDIA_PLAY_PAUSE")
                pad("forward.fill", "KEYCODE_MEDIA_FAST_FORWARD")
            }
            HStack(spacing: 18) {
                pad("speaker.slash.fill", "KEYCODE_VOLUME_MUTE")
                pad("speaker.minus.fill", "KEYCODE_VOLUME_DOWN")
                pad("speaker.plus.fill", "KEYCODE_VOLUME_UP")
            }
            HStack(spacing: 6) {
                TextField("Type on the TV", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { send() }
                Button { send() } label: { Image(systemName: "return") }
                    .disabled(text.isEmpty)
            }
            .padding(.horizontal, 16)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(TVRemote.apps) { app in
                    Button { remote.open(app.package) } label: {
                        VStack(spacing: 2) {
                            Image(systemName: app.symbol).font(.system(size: 13))
                            Text(app.name).font(.system(size: 8)).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.07)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            Spacer(minLength: 0)
        }
        .padding(.bottom, 12)
        .frame(width: 260, height: 520)
        .disabled(remote.state != .ready && remote.state != .noADB && !isRefused)
        .background(KeyCatcher { remote.key($0) })
    }

    private var isRefused: Bool {
        if case .refused = remote.state { return true }
        return false
    }

    private var dpad: some View {
        ZStack {
            Circle().fill(Color.primary.opacity(0.08)).frame(width: 150, height: 150)
            VStack(spacing: 4) {
                arrow("chevron.up", "KEYCODE_DPAD_UP")
                HStack(spacing: 4) {
                    arrow("chevron.left", "KEYCODE_DPAD_LEFT")
                    Button { remote.key("KEYCODE_DPAD_CENTER") } label: {
                        Text("OK").font(.system(size: 13, weight: .bold))
                            .frame(width: 54, height: 54)
                            .background(Circle().fill(Color.primary.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                    arrow("chevron.right", "KEYCODE_DPAD_RIGHT")
                }
                arrow("chevron.down", "KEYCODE_DPAD_DOWN")
            }
        }
    }

    private func arrow(_ symbol: String, _ code: String) -> some View {
        Button { remote.key(code) } label: {
            Image(systemName: symbol).font(.system(size: 15, weight: .bold)).frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func pad(_ symbol: String, _ code: String, tint: Color = .primary) -> some View {
        Button { remote.key(code) } label: {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.primary.opacity(0.09)))
        }
        .buttonStyle(.plain)
    }

    private func message(_ text: String, detail: String?) -> some View {
        VStack(spacing: 3) {
            Text(text).font(.system(size: 11)).multilineTextAlignment(.center)
            if let detail {
                Text(detail).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
    }

    private func send() {
        remote.type(text)
        text = ""
    }
}

/// The Mac's arrow keys, Return, Escape and Delete work the remote while its window is in front (and the text box
/// isn't being typed in).
private struct KeyCatcher: NSViewRepresentable {
    let onKey: (String) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = KeyView()
        v.onKey = onKey
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class KeyView: NSView {
        var onKey: ((String) -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.window, event.window === window,
                      !(window.firstResponder is NSTextView) else { return event }
                let codes: [UInt16: String] = [
                    126: "KEYCODE_DPAD_UP", 125: "KEYCODE_DPAD_DOWN", 123: "KEYCODE_DPAD_LEFT",
                    124: "KEYCODE_DPAD_RIGHT", 36: "KEYCODE_DPAD_CENTER", 76: "KEYCODE_DPAD_CENTER",
                    53: "KEYCODE_BACK", 51: "KEYCODE_BACK", 49: "KEYCODE_MEDIA_PLAY_PAUSE",
                ]
                guard let code = codes[event.keyCode] else { return event }
                self.onKey?(code)
                return nil
            }
        }
    }
}
