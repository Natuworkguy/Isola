import AppKit
import Foundation
import Network
import SwiftUI
import UniformTypeIdentifiers

// MARK: The TVs on the network

/// A TV or speaker Isola can reach: a Google Cast device (Chromecast, Google TV, Android TV, a Nest speaker) or an
/// AirPlay one (Apple TV, an AirPlay TV or speaker).
struct TVDevice: Identifiable, Equatable {
    enum Kind { case cast, airplay }
    let id: String
    let name: String
    let model: String
    let kind: Kind
    let endpoint: NWEndpoint

    var symbol: String {
        let m = model.lowercased()
        if kind == .airplay { return m.contains("appletv") ? "appletv.fill" : "airplayvideo" }
        if m.contains("speaker") || m.contains("nest audio") || m.contains("home mini") || m.contains("audio") {
            return "hifispeaker.fill"
        }
        return "tv.fill"
    }

    static func == (a: TVDevice, b: TVDevice) -> Bool { a.id == b.id && a.name == b.name }
}

/// What a Cast TV is doing: the app it runs, and what that app plays if it says.
struct TVPlaying: Equatable {
    var app = ""
    var appID = ""
    var status = ""
    var title = ""
    var subtitle = ""
    var artwork: URL?
    var state = ""            // PLAYING, PAUSED, BUFFERING, IDLE
    var position: Double = 0
    var duration: Double = 0
    var at = Date()
    var volume: Double = 0.5
    var muted = false
    var canControl = false

    var playing: Bool { state == "PLAYING" || state == "BUFFERING" }
    var idle: Bool { app.isEmpty || app == "Backdrop" || appID == "E8C28D3C" }

    /// Where it is now, counting on from the last report while it plays.
    var now: Double {
        guard playing else { return position }
        let t = position + Date().timeIntervalSince(at)
        return duration > 0 ? min(t, duration) : t
    }
}

/// Finds the TVs on the network, keeps a line open to the chosen Cast one, and sends it things to play.
final class TVs: ObservableObject {
    static let shared = TVs()

    @Published private(set) var devices: [TVDevice] = []
    @Published var chosenID: String = UserDefaults.standard.string(forKey: "tv.chosen") ?? "" {
        didSet {
            UserDefaults.standard.set(chosenID, forKey: "tv.chosen")
            connectChosen()
        }
    }
    @Published private(set) var playing = TVPlaying()
    @Published private(set) var connected = false
    @Published var note = ""

    private var browsers: [NWBrowser] = []
    private var found: [String: TVDevice] = [:]
    private var link: CastLink?
    private let server = CastFileServer()
    private var started = false

    var chosen: TVDevice? {
        devices.first { $0.id == chosenID } ?? devices.first { $0.kind == .cast }
    }

    func start() {
        guard !started else { return }
        started = true
        browse("_googlecast._tcp", kind: .cast)
        browse("_airplay._tcp", kind: .airplay)
    }

    private func browse(_ type: String, kind: TVDevice.Kind) {
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: type, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            DispatchQueue.main.async { self?.update(results, kind: kind) }
        }
        browser.start(queue: .main)
        browsers.append(browser)
    }

    private func update(_ results: Set<NWBrowser.Result>, kind: TVDevice.Kind) {
        found = found.filter { $0.value.kind != kind }
        for result in results {
            guard case let .service(service, _, _, _) = result.endpoint else { continue }
            var name = service
            var model = ""
            if case let .bonjour(txt) = result.metadata {
                if kind == .cast {
                    name = txt["fn"] ?? service
                    model = txt["md"] ?? ""
                } else {
                    model = txt["model"] ?? ""
                }
            }
            let id = (kind == .cast ? "cast:" : "airplay:") + service
            found[id] = TVDevice(id: id, name: name, model: model, kind: kind, endpoint: result.endpoint)
        }
        // an AirPlay speaker that is also a Cast one shows once, as Cast (it can do more that way)
        let castNames = Set(found.values.filter { $0.kind == .cast }.map(\.name))
        let list = found.values.filter { $0.kind == .cast || !castNames.contains($0.name) }
            .sorted { ($0.kind == .cast ? 0 : 1, $0.name) < ($1.kind == .cast ? 0 : 1, $1.name) }
        if list != devices {
            devices = list
            if link == nil { connectChosen() }
        }
    }

    private func connectChosen() {
        guard let device = chosen, device.kind == .cast else {
            link?.close()
            link = nil
            connected = false
            playing = TVPlaying()
            return
        }
        if link?.device.id == device.id { return }
        link?.close()
        let link = CastLink(device: device)
        link.onChange = { [weak self, weak link] state, isConnected in
            guard let self, let link, self.link === link else { return }
            self.playing = state
            self.connected = isConnected
        }
        link.start()
        self.link = link
    }

    // MARK: Controls

    func playPause() {
        if playing.playing { link?.media("PAUSE") } else { link?.media("PLAY") }
    }
    func skip(_ seconds: Double) { link?.seek(max(0, playing.now + seconds)) }
    func seek(to seconds: Double) { link?.seek(seconds) }
    func setVolume(_ level: Double) { link?.setVolume(level) }
    func toggleMute() { link?.setMuted(!playing.muted) }
    func volumeStep(_ delta: Double) { link?.setVolume(min(1, max(0, playing.volume + delta))) }
    func stopApp() { link?.stopApp() }

    // MARK: Sending things to the TV

    /// A file on this Mac: a video, a song or a picture. Isola serves it on the network while the TV plays it.
    func cast(file: URL) {
        guard let link, let device = chosen else { return say("Choose a Cast TV first.") }
        guard let type = UTType(filenameExtension: file.pathExtension), let mime = type.preferredMIMEType,
              type.conforms(to: .audiovisualContent) || type.conforms(to: .image) else {
            return say("A TV can play videos, music and pictures, not \(file.pathExtension.uppercased()) files.")
        }
        link.localAddress { [weak self] host in
            guard let self else { return }
            guard let host, let url = self.server.serve(file, host: host) else {
                return self.say("Couldn't share the file on the network.")
            }
            link.load(url: url, mime: mime, title: file.deletingPathExtension().lastPathComponent,
                      image: type.conforms(to: .image))
            self.say("Playing on \(device.name)")
        }
    }

    /// A link: a YouTube video, or a direct video, music or picture address.
    func cast(link address: URL) {
        guard let link, let device = chosen else { return say("Choose a Cast TV first.") }
        if let id = Self.youTubeID(address) {
            link.youTube(id)
            return say("Opening on \(device.name)'s YouTube")
        }
        let ext = address.pathExtension.lowercased()
        let mime: String? = ext == "m3u8" ? "application/x-mpegURL" : ext == "mpd" ? "application/dash+xml"
            : UTType(filenameExtension: ext)?.preferredMIMEType
        guard let mime, mime.hasPrefix("video") || mime.hasPrefix("audio") || mime.hasPrefix("image")
                || ext == "m3u8" || ext == "mpd" else {
            return say("That page isn't a video. YouTube links, and links straight to a video, song or picture, work.")
        }
        link.load(url: address, mime: mime, title: address.lastPathComponent, image: mime.hasPrefix("image"))
        say("Playing on \(device.name)")
    }

    /// Safari's front page, if it is something a TV can play.
    func castSafariPage() {
        guard let page = Safari.frontPage() else { return say("Nothing open in Safari.") }
        cast(link: page.url)
    }

    /// Whatever link is on the clipboard.
    func castClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: text), url.scheme?.hasPrefix("http") == true else {
            return say("No link on the clipboard.")
        }
        cast(link: url)
    }

    /// Music's sound to an AirPlay TV or speaker, by name (Music does the AirPlay itself).
    func sendMusic(to device: TVDevice) {
        let name = device.name.replacingOccurrences(of: "\"", with: "\\\"")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let (_, error) = Safari.run("""
            tell application "Music"
                set current AirPlay devices to {AirPlay device "\(name)"}
            end tell
            """)
            DispatchQueue.main.async {
                self?.say(error == nil ? "Music is playing on \(device.name)" : "Music couldn't find \(device.name).")
            }
        }
    }

    /// The Mac's screen on an AirPlay TV: Displays settings, where the TV is in the add-display menu.
    func mirror() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
        say("Choose the TV under the + in Displays")
    }

    private func say(_ text: String) {
        note = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            if self?.note == text { self?.note = "" }
        }
    }

    static func youTubeID(_ url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        if host.hasSuffix("youtu.be") { return url.pathComponents.dropFirst().first }
        guard host.hasSuffix("youtube.com") else { return nil }
        if let v = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value {
            return v
        }
        let parts = url.pathComponents
        if let i = parts.firstIndex(where: { $0 == "shorts" || $0 == "embed" || $0 == "live" }), i + 1 < parts.count {
            return parts[i + 1]
        }
        return nil
    }
}

// MARK: The Cast protocol

/// One line to a Cast device: TLS on port 8009, carrying length-prefixed protocol-buffer messages, each a JSON
/// string on a namespace. It follows the receiver (which app runs, the volume) and, when that app plays media,
/// the media session (what, where, paused or not).
final class CastLink {
    let device: TVDevice
    var onChange: ((TVPlaying, Bool) -> Void)?

    private let queue = DispatchQueue(label: "isola.cast")
    private var connection: NWConnection?
    private var buffer = Data()
    private var requestID = 1
    private var heartbeat: DispatchSourceTimer?
    private var state = TVPlaying()
    private var transport = ""          // the running app's transport id
    private var sessionID = ""
    private var mediaSession = 0
    private var joined: Set<String> = []
    private var pending: [(String) -> Void] = []     // things to do once the wanted app is running
    private var wantedApp = ""
    private var closed = false
    private var lastPong = Date()

    static let receiver = "urn:x-cast:com.google.cast.receiver"
    static let mediaNS = "urn:x-cast:com.google.cast.media"
    static let connectionNS = "urn:x-cast:com.google.cast.tp.connection"
    static let heartbeatNS = "urn:x-cast:com.google.cast.tp.heartbeat"
    static let youTubeNS = "urn:x-cast:com.google.youtube.mdx"
    static let defaultReceiver = "CC1AD845"
    static let youTubeApp = "233637DE"

    init(device: TVDevice) { self.device = device }

    func start() {
        let tls = NWProtocolTLS.Options()
        // a Cast device's certificate is its own, signed by Google for the device; there is no name to check it by
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, _, complete in complete(true) }, queue)
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 6
        let conn = NWConnection(to: device.endpoint, using: NWParameters(tls: tls, tcp: tcp))
        conn.stateUpdateHandler = { [weak self, weak conn] st in
            guard let self, let conn, self.connection === conn else { return }
            switch st {
            case .ready:
                self.lastPong = Date()
                self.send(Self.connectionNS, to: "receiver-0", ["type": "CONNECT"])
                self.send(Self.receiver, to: "receiver-0", ["type": "GET_STATUS"])
                self.startHeartbeat()
                self.publish(true)
                self.receive()
            case .failed, .cancelled:
                self.publish(false)
                self.retry()
            default: break
            }
        }
        connection = conn
        conn.start(queue: queue)
    }

    func close() {
        queue.async {
            self.closed = true
            self.heartbeat?.cancel()
            self.connection?.cancel()
        }
    }

    private func retry() {
        guard !closed else { return }
        heartbeat?.cancel()
        heartbeat = nil
        let old = connection
        connection = nil
        old?.cancel()
        joined = []
        buffer = Data()
        queue.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, !self.closed, self.connection == nil else { return }
            self.start()
        }
    }

    private func startHeartbeat() {
        heartbeat?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 5, repeating: 5)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            if Date().timeIntervalSince(self.lastPong) > 20 {
                self.connection?.cancel()      // gone quiet: start over
                return
            }
            self.send(Self.heartbeatNS, to: "receiver-0", ["type": "PING"])
            // media apps don't always report progress; ask now and then while something plays
            if self.state.playing, !self.transport.isEmpty, self.state.canControl {
                self.send(Self.mediaNS, to: self.transport, ["type": "GET_STATUS"])
            }
        }
        t.resume()
        heartbeat = t
    }

    private func publish(_ isConnected: Bool) {
        let s = state
        DispatchQueue.main.async { self.onChange?(s, isConnected) }
    }

    // MARK: Asks

    func media(_ type: String) {
        queue.async {
            guard !self.transport.isEmpty, self.mediaSession != 0 else { return }
            self.send(Self.mediaNS, to: self.transport, ["type": type, "mediaSessionId": self.mediaSession])
        }
    }

    func seek(_ seconds: Double) {
        queue.async {
            guard !self.transport.isEmpty, self.mediaSession != 0 else { return }
            self.send(Self.mediaNS, to: self.transport,
                      ["type": "SEEK", "mediaSessionId": self.mediaSession, "currentTime": seconds])
            self.state.position = seconds
            self.state.at = Date()
            self.publish(true)
        }
    }

    func setVolume(_ level: Double) {
        queue.async {
            self.send(Self.receiver, to: "receiver-0", ["type": "SET_VOLUME", "volume": ["level": level]])
            self.state.volume = level
            self.publish(true)
        }
    }

    func setMuted(_ muted: Bool) {
        queue.async { self.send(Self.receiver, to: "receiver-0", ["type": "SET_VOLUME", "volume": ["muted": muted]]) }
    }

    func stopApp() {
        queue.async {
            guard !self.sessionID.isEmpty else { return }
            self.send(Self.receiver, to: "receiver-0", ["type": "STOP", "sessionId": self.sessionID])
        }
    }

    /// Our address on the network the TV is on (the one this connection goes out from).
    func localAddress(_ done: @escaping (String?) -> Void) {
        queue.async {
            var host: String?
            if case let .hostPort(h, _) = self.connection?.currentPath?.localEndpoint {
                switch h {
                case .ipv4(let a): host = "\(a)"
                case .ipv6(let a): host = "[\("\(a)".components(separatedBy: "%").first ?? "")]"
                case .name(let n, _): host = n
                @unknown default: host = nil
                }
            }
            DispatchQueue.main.async { done(host) }
        }
    }

    func load(url: URL, mime: String, title: String, image: Bool) {
        whenRunning(Self.defaultReceiver) { [weak self] transport in
            guard let self else { return }
            var media: [String: Any] = [
                "contentId": url.absoluteString,
                "contentType": mime,
                "streamType": image ? "NONE" : "BUFFERED",
                "metadata": ["metadataType": image ? 4 : (mime.hasPrefix("audio") ? 3 : 0), "title": title],
            ]
            if mime.contains("mpegURL") { media["streamType"] = "LIVE" }
            self.send(Self.mediaNS, to: transport, ["type": "LOAD", "media": media, "autoplay": true, "currentTime": 0])
        }
    }

    func youTube(_ id: String) {
        whenRunning(Self.youTubeApp) { [weak self] transport in
            guard let self else { return }
            self.send(Self.youTubeNS, to: transport, ["type": "flingVideo", "data": ["currentTime": 0, "videoId": id]])
            // Older YouTube receivers ignore the fling; the TV's DIAL server opens the video directly
            self.queue.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self, !self.state.playing else { return }
                self.dialYouTube(id)
            }
        }
    }

    private func dialYouTube(_ id: String) {
        guard case let .hostPort(host, _) = connection?.currentPath?.remoteEndpoint else { return }
        var h = "\(host)"
        if case .ipv6 = host { h = "[\(h.components(separatedBy: "%").first ?? h)]" }
        guard let url = URL(string: "http://\(h):8008/apps/YouTube") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = "v=\(id)".data(using: .utf8)
        req.timeoutInterval = 5
        URLSession.shared.dataTask(with: req).resume()
    }

    private func whenRunning(_ app: String, _ then: @escaping (String) -> Void) {
        queue.async {
            if self.state.appID == app, !self.transport.isEmpty {
                then(self.transport)
                return
            }
            self.wantedApp = app
            self.pending.append(then)
            self.send(Self.receiver, to: "receiver-0", ["type": "LAUNCH", "appId": app])
        }
    }

    // MARK: Wire

    private func send(_ namespace: String, to destination: String, _ body: [String: Any]) {
        var payload = body
        if namespace != Self.connectionNS && namespace != Self.heartbeatNS {
            payload["requestId"] = requestID
            requestID += 1
        }
        guard let json = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: json, encoding: .utf8) else { return }
        var msg = Data()
        Proto.varintField(1, 0, into: &msg)                // CASTV2_1_0
        Proto.stringField(2, "sender-isola", into: &msg)
        Proto.stringField(3, destination, into: &msg)
        Proto.stringField(4, namespace, into: &msg)
        Proto.varintField(5, 0, into: &msg)                // a string payload
        Proto.stringField(6, text, into: &msg)
        var frame = Data()
        var length = UInt32(msg.count).bigEndian
        withUnsafeBytes(of: &length) { frame.append(contentsOf: $0) }
        frame.append(msg)
        connection?.send(content: frame, completion: .contentProcessed { _ in })
    }

    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, error in
            guard let self else { return }
            if let data { self.buffer.append(data); self.drain() }
            if done || error != nil {
                self.connection?.cancel()
                return
            }
            self.receive()
        }
    }

    private func drain() {
        while buffer.count >= 4 {
            let b = [UInt8](buffer.prefix(4))
            let n = Int(b[0]) << 24 | Int(b[1]) << 16 | Int(b[2]) << 8 | Int(b[3])
            guard buffer.count >= 4 + n else { return }
            let body = buffer.subdata(in: buffer.startIndex + 4 ..< buffer.startIndex + 4 + n)
            buffer.removeSubrange(buffer.startIndex ..< buffer.startIndex + 4 + n)
            buffer = Data(buffer)
            let fields = Proto.strings(body)
            guard let ns = fields[4], let text = fields[6], let data = text.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            handle(ns, from: fields[2] ?? "", json)
        }
    }

    private func handle(_ ns: String, from source: String, _ json: [String: Any]) {
        let type = json["type"] as? String ?? ""
        switch (ns, type) {
        case (Self.heartbeatNS, "PING"):
            send(Self.heartbeatNS, to: source, ["type": "PONG"])
            lastPong = Date()
        case (Self.heartbeatNS, _):
            lastPong = Date()
        case (Self.receiver, "RECEIVER_STATUS"):
            receiverStatus(json["status"] as? [String: Any] ?? [:])
        case (Self.mediaNS, "MEDIA_STATUS"):
            mediaStatus((json["status"] as? [[String: Any]])?.first)
        case (Self.connectionNS, "CLOSE"):
            joined.remove(source)
        default: break
        }
    }

    private func receiverStatus(_ status: [String: Any]) {
        lastPong = Date()
        if let volume = status["volume"] as? [String: Any] {
            if let level = volume["level"] as? Double { state.volume = level }
            if let muted = volume["muted"] as? Bool { state.muted = muted }
        }
        let app = (status["applications"] as? [[String: Any]])?.first
        let appID = app?["appId"] as? String ?? ""
        let newTransport = app?["transportId"] as? String ?? ""
        let spaces = (app?["namespaces"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        if appID != state.appID || newTransport != transport {
            // a different app: what the old one played is gone
            state.title = ""; state.subtitle = ""; state.artwork = nil; state.state = ""
            state.position = 0; state.duration = 0
            mediaSession = 0
        }
        state.app = app?["displayName"] as? String ?? ""
        state.appID = appID
        state.status = app?["statusText"] as? String ?? ""
        sessionID = app?["sessionId"] as? String ?? ""
        transport = newTransport
        state.canControl = spaces.contains(Self.mediaNS)
        if !transport.isEmpty, !joined.contains(transport) {
            joined.insert(transport)
            send(Self.connectionNS, to: transport, ["type": "CONNECT"])
            if state.canControl { send(Self.mediaNS, to: transport, ["type": "GET_STATUS"]) }
        }
        if !wantedApp.isEmpty, appID == wantedApp, !transport.isEmpty {
            let todo = pending
            pending = []
            wantedApp = ""
            let t = transport
            // a moment for the app to settle before it is asked to play
            queue.asyncAfter(deadline: .now() + 0.6) { todo.forEach { $0(t) } }
        }
        publish(true)
    }

    private func mediaStatus(_ s: [String: Any]?) {
        guard let s else {
            state.state = "IDLE"
            mediaSession = 0
            publish(true)
            return
        }
        if let id = s["mediaSessionId"] as? Int { mediaSession = id }
        if let player = s["playerState"] as? String { state.state = player }
        if let t = s["currentTime"] as? Double { state.position = t; state.at = Date() }
        if let media = s["media"] as? [String: Any] {
            if let d = media["duration"] as? Double { state.duration = d }
            if let meta = media["metadata"] as? [String: Any] {
                state.title = meta["title"] as? String ?? state.title
                state.subtitle = (meta["subtitle"] as? String) ?? (meta["artist"] as? String)
                    ?? (meta["seriesTitle"] as? String) ?? state.subtitle
                if let img = (meta["images"] as? [[String: Any]])?.first?["url"] as? String {
                    state.artwork = URL(string: img)
                }
            }
        }
        publish(true)
    }
}

/// Just enough protocol buffers for the Cast message: varints and length-delimited strings.
enum Proto {
    static func varint(_ value: UInt64, into data: inout Data) {
        var v = value
        while v >= 0x80 {
            data.append(UInt8(v & 0x7f) | 0x80)
            v >>= 7
        }
        data.append(UInt8(v))
    }

    static func varintField(_ field: Int, _ value: UInt64, into data: inout Data) {
        varint(UInt64(field << 3), into: &data)
        varint(value, into: &data)
    }

    static func stringField(_ field: Int, _ text: String, into data: inout Data) {
        let bytes = Data(text.utf8)
        varint(UInt64(field << 3 | 2), into: &data)
        varint(UInt64(bytes.count), into: &data)
        data.append(bytes)
    }

    /// The string fields of a message, by number (other kinds are skipped).
    static func strings(_ data: Data) -> [Int: String] {
        let b = [UInt8](data)
        var out: [Int: String] = [:]
        var i = 0
        func readVarint() -> UInt64? {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while i < b.count {
                let byte = b[i]
                i += 1
                result |= UInt64(byte & 0x7f) << shift
                if byte < 0x80 { return result }
                shift += 7
                if shift > 63 { return nil }
            }
            return nil
        }
        while i < b.count {
            guard let key = readVarint() else { break }
            let field = Int(key >> 3)
            switch key & 7 {
            case 0: _ = readVarint()
            case 2:
                guard let n = readVarint(), i + Int(n) <= b.count else { return out }
                out[field] = String(decoding: b[i ..< i + Int(n)], as: UTF8.self)
                i += Int(n)
            case 1: i += 8
            case 5: i += 4
            default: return out
            }
        }
        return out
    }
}

// MARK: Serving a file to the TV

/// A small web server for the file being played on the TV, with ranges, so the TV can seek in a long video.
/// Only the one file it was given is served, under a random name.
final class CastFileServer {
    private var listener: NWListener?
    private var files: [String: URL] = [:]
    private let queue = DispatchQueue(label: "isola.cast-files")

    func serve(_ file: URL, host: String) -> URL? {
        if listener == nil {
            guard let l = try? NWListener(using: .tcp) else { return nil }
            l.newConnectionHandler = { [weak self] c in self?.accept(c) }
            l.start(queue: queue)
            listener = l
            // the port is known once it is listening
            for _ in 0 ..< 40 where l.port == nil { Thread.sleep(forTimeInterval: 0.025) }
        }
        guard let port = listener?.port?.rawValue else { return nil }
        let key = UUID().uuidString.prefix(12).lowercased()
        let name = file.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "file"
        queue.sync { files = [String(key): file] }      // only the latest file stays shared
        return URL(string: "http://\(host):\(port)/\(key)/\(name)")
    }

    private func accept(_ c: NWConnection) {
        c.start(queue: queue)
        c.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else { return c.cancel() }
            self.answer(request, on: c)
        }
    }

    private func answer(_ request: String, on c: NWConnection) {
        let lines = request.components(separatedBy: "\r\n")
        let parts = lines.first?.components(separatedBy: " ") ?? []
        guard parts.count >= 2, let key = parts[1].split(separator: "/").first, let file = files[String(key)],
              let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value,
              let handle = try? FileHandle(forReadingFrom: file) else {
            c.send(content: "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".data(using: .utf8),
                   completion: .contentProcessed { _ in c.cancel() })
            return
        }
        var start: Int64 = 0
        var end: Int64 = size - 1
        var partial = false
        if let range = lines.first(where: { $0.lowercased().hasPrefix("range: bytes=") }) {
            let spec = range.dropFirst("range: bytes=".count).split(separator: "-", omittingEmptySubsequences: false)
            if let s = spec.first, let v = Int64(s) { start = v }
            if spec.count > 1, let v = Int64(spec[1]) { end = min(v, size - 1) }
            partial = true
        }
        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let length = max(0, end - start + 1)
        var head = partial ? "HTTP/1.1 206 Partial Content\r\n" : "HTTP/1.1 200 OK\r\n"
        head += "Content-Type: \(mime)\r\nContent-Length: \(length)\r\nAccept-Ranges: bytes\r\n"
        if partial { head += "Content-Range: bytes \(start)-\(end)/\(size)\r\n" }
        head += "Access-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n"
        let isHead = parts[0] == "HEAD"
        c.send(content: head.data(using: .utf8), completion: .contentProcessed { [weak self] _ in
            if isHead { handle.closeFile(); c.cancel(); return }
            try? handle.seek(toOffset: UInt64(start))
            self?.pump(handle, left: length, on: c)
        })
    }

    private func pump(_ handle: FileHandle, left: Int64, on c: NWConnection) {
        guard left > 0 else { handle.closeFile(); c.cancel(); return }
        let chunk = handle.readData(ofLength: Int(min(left, 256 * 1024)))
        guard !chunk.isEmpty else { handle.closeFile(); c.cancel(); return }
        c.send(content: chunk, completion: .contentProcessed { [weak self] error in
            if error != nil { handle.closeFile(); c.cancel(); return }
            self?.pump(handle, left: left - Int64(chunk.count), on: c)
        })
    }
}

// MARK: The TV widget

/// The TV: which one, what it plays, and its controls. Drop a video, song or picture on it to play it there.
struct TVWidget: View {
    @ObservedObject var tvs: TVs
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                WidgetHeader(widget: .tv)
                Spacer(minLength: 0)
                devicePicker
            }
            if let device = tvs.chosen {
                if device.kind == .cast { castBody(device) } else { airplayBody(device) }
            } else {
                Spacer(minLength: 0)
                VStack(spacing: 4) {
                    Image(systemName: "tv").font(.system(size: 22))
                    Text("Looking for TVs…").font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                }
                .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
        }
        .overlay {
            if targeted {
                RoundedRectangle(cornerRadius: 14).strokeBorder(Color.accentColor, lineWidth: 2)
                    .overlay(Label("Play on the TV", systemImage: "tv").font(.system(size: 11, weight: .semibold)))
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.6)))
            }
        }
        .onDrop(of: [.fileURL, .url], isTargeted: $targeted) { providers in drop(providers) }
        .onAppear { tvs.start() }
    }

    private var devicePicker: some View {
        Menu {
            ForEach(tvs.devices) { device in
                Button {
                    tvs.chosenID = device.id
                } label: {
                    Label(device.name, systemImage: device.id == tvs.chosen?.id ? "checkmark" : device.symbol)
                }
            }
            if tvs.devices.isEmpty { Text("No TVs found on this network") }
        } label: {
            Text(tvs.chosen?.name ?? "Choose")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.1)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    @ViewBuilder private func castBody(_ device: TVDevice) -> some View {
        let p = tvs.playing
        HStack(spacing: 8) {
            artwork(p)
            VStack(alignment: .leading, spacing: 1) {
                Text(!p.title.isEmpty ? p.title : (p.idle ? (tvs.connected ? "Nothing playing" : "Connecting…") : p.app))
                    .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(!p.subtitle.isEmpty ? p.subtitle : (!p.title.isEmpty ? p.app : p.status))
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        if p.duration > 0 {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let now = tvs.playing.now
                HStack(spacing: 5) {
                    Text(Self.clock(now)).font(.system(size: 8, weight: .medium).monospacedDigit())
                    WidgetBar(value: now / max(1, p.duration), color: .white.opacity(0.85))
                        .overlay(GeometryReader { g in
                            Color.clear.contentShape(Rectangle()).onTapGesture { location in
                                tvs.seek(to: Double(location.x / max(1, g.size.width)) * p.duration)
                            }
                        })
                    Text(Self.clock(p.duration)).font(.system(size: 8, weight: .medium).monospacedDigit())
                }
                .foregroundStyle(.white.opacity(0.6))
            }
        }
        Spacer(minLength: 0)
        HStack(spacing: 6) {
            if p.canControl {
                WidgetButton(symbol: "gobackward.10", size: 24) { tvs.skip(-10) }
                WidgetButton(symbol: p.playing ? "pause.fill" : "play.fill", size: 28) { tvs.playPause() }
                WidgetButton(symbol: "goforward.30", size: 24) { tvs.skip(30) }
            }
            Spacer(minLength: 0)
            WidgetButton(symbol: p.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", size: 24) { tvs.toggleMute() }
            Slider(value: Binding(get: { tvs.playing.volume }, set: { tvs.setVolume($0) }), in: 0 ... 1)
                .controlSize(.mini)
                .frame(width: 56)
            castMenu(p)
        }
        if !tvs.note.isEmpty {
            Text(tvs.note).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
        }
    }

    private func castMenu(_ p: TVPlaying) -> some View {
        Menu {
            Button { tvs.castSafariPage() } label: { Label("Play Safari's video here", systemImage: "safari") }
            Button { tvs.castClipboard() } label: { Label("Play the copied link", systemImage: "link") }
            Button { pickFile() } label: { Label("Play a file from this Mac…", systemImage: "folder") }
            if !p.idle {
                Divider()
                Button(role: .destructive) { tvs.stopApp() } label: { Label("Stop \(p.app)", systemImage: "stop.fill") }
            }
        } label: {
            Image(systemName: "airplayvideo")
                .font(.system(size: 10, weight: .bold))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(0.18)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Play something on the TV")
    }

    @ViewBuilder private func airplayBody(_ device: TVDevice) -> some View {
        Spacer(minLength: 0)
        HStack(spacing: 6) {
            Button { tvs.sendMusic(to: device) } label: {
                Label("Music here", systemImage: "music.note").font(.system(size: 10, weight: .semibold))
            }
            Button { tvs.mirror() } label: {
                Label("Mirror screen", systemImage: "rectangle.on.rectangle").font(.system(size: 10, weight: .semibold))
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        Text(tvs.note.isEmpty ? "AirPlay: send Music's sound or this screen." : tvs.note)
            .font(.system(size: 9)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
        Spacer(minLength: 0)
    }

    private func artwork(_ p: TVPlaying) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.1))
            if let url = p.artwork {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.clear }
            } else {
                Image(systemName: tvs.chosen?.symbol ?? "tv.fill").font(.system(size: 15)).foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(width: 38, height: 38)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func drop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { tvs.cast(file: url) }
            }
            return true
        }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            DispatchQueue.main.async { tvs.cast(link: url) }
        }
        return true
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audiovisualContent, .image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a video, song or picture to play on the TV"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url { tvs.cast(file: url) }
    }

    static func clock(_ t: Double) -> String {
        let s = Int(max(0, t))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}
