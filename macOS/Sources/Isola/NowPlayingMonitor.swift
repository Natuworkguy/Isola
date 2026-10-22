import AppKit
import SwiftUI

/// One app playing media, as the Media tab lists it when there is more than one.
struct NowPlayer: Identifiable {
    var id: String { info.bundleID }
    let info: MediaInfo
    let name: String
    let icon: NSImage?
    let artwork: NSImage?
    let tint: Color
    /// The app macOS reports as now playing: the only one the Mac's media commands reach.
    let controllable: Bool

    var isPlaying: Bool { info.isPlaying }
}

final class NowPlayingMonitor: ObservableObject {
    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var isPlaying = false
    @Published private(set) var hasTrack = false
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var sourceName = ""
    @Published private(set) var sourceIcon: NSImage?
    @Published private(set) var tint: Color = Color(white: 0.7)
    /// True while showing an app macOS no longer reports as now playing (see backgroundPlayer). The Mac's media
    /// commands only reach the app macOS reports, so the controls are off meanwhile.
    @Published private(set) var isBackground = false
    @Published private(set) var artwork: NSImage? {
        didSet { tint = artwork?.vibrantColor ?? Color(white: 0.7) }
    }
    /// Every app playing, the one on screen first, when there is more than one. Empty otherwise.
    @Published private(set) var players: [NowPlayer] = []

    fileprivate var remote: MediaRemoteStream?
    fileprivate var usingRemote = false
    fileprivate var latest: MediaInfo?
    /// What is on screen: the latest report, or a background player standing in for it.
    fileprivate var shown: MediaInfo?
    /// The last report from each app that was playing when it was last heard from.
    private var remembered: [String: MediaInfo] = [:]
    private var lastBackgroundCheck = Date.distantPast
    fileprivate var scriptApp: PlayerApp?
    fileprivate var scriptTimer: Timer?
    fileprivate var scriptArtworkKey = ""
    fileprivate var holdUntil = Date.distantPast
    private var tickTimer: Timer?
    private var sourceBundleID = ""
    private var artworkSignature = ""
    private var playersSignature = ""
    private var artworkCache: [String: (signature: String, image: NSImage?, tint: Color)] = [:]
    private var appCache: [String: (name: String, icon: NSImage?)] = [:]

    func start() {
        startScripts()

        NotificationCenter.default.addObserver(forName: .isolaTrimMemory, object: nil, queue: .main) { [weak self] _ in
            self?.artworkCache.removeAll()
        }
        let ticker = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(ticker, forMode: .common)
        tickTimer = ticker

        guard let stream = MediaRemoteStream() else { return }
        stream.selfTest { [weak self] passed in
            guard passed, let self else { return }
            self.stopScripts()
            stream.onInfo = { [weak self] info in self?.apply(info) }
            stream.onFailure = { [weak self] in self?.fallBackToScripts() }
            self.remote = stream
            self.usingRemote = true
            stream.start()
        }
    }

    func stop() {
        tickTimer?.invalidate()
        tickTimer = nil
        stopScripts()
        remote?.stop()
    }

    enum Command {
        case playPause, next, previous

        /// MediaRemote's command number.
        var code: Int {
            switch self {
            case .playPause: return 2
            case .next: return 4
            case .previous: return 5
            }
        }

        /// The AppleScript verb, for Music and Spotify without MediaRemote.
        var verb: String {
            switch self {
            case .playPause: return "playpause"
            case .next: return "next track"
            case .previous: return "previous track"
            }
        }
    }

    func togglePlayPause() {
        guard !isBackground else { return }
        let target = !isPlaying
        holdUntil = Date().addingTimeInterval(1.5)
        withAnimation(.snappy(duration: 0.25)) { isPlaying = target }
        send(.playPause)
    }

    func next() {
        guard !isBackground else { return }
        position = 0
        send(.next)
    }

    func previous() {
        guard !isBackground else { return }
        position = 0
        send(.previous)
    }

    /// A command from the Media tab's list. Only the app macOS reports can take one; any other is brought forward.
    func perform(_ command: Command, on player: NowPlayer) {
        guard player.controllable else {
            reveal(player)
            return
        }
        send(command)
    }

    func reveal(_ player: NowPlayer) {
        _ = NSRunningApplication.runningApplications(withBundleIdentifier: player.id).first?.activate()
    }

    private func send(_ command: Command) {
        if usingRemote {
            remote?.send(command.code)
        } else {
            scriptCommand(command.verb)
        }
    }

    func seek(to seconds: Double) {
        guard !isBackground else { return }
        let target = max(0, min(seconds, duration))
        position = target
        if usingRemote {
            latest?.elapsed = target
            latest?.timestamp = Date()
            shown = latest
            remote?.seek(micros: Int(target * 1_000_000))
        } else if let app = scriptApp {
            _ = runScript("tell application \"\(app.rawValue)\" to set player position to \(Int(target))")
        }
    }

    private func tick() {
        guard usingRemote else { return }
        // Other apps start and stop without macOS saying so: look again every couple of seconds.
        if !remembered.isEmpty || !players.isEmpty, Date().timeIntervalSince(lastBackgroundCheck) > 2 {
            lastBackgroundCheck = Date()
            refreshBackground()
        }
        guard hasTrack, let info = shown else { return }
        position = livePosition(info)
    }

    private func livePosition(_ info: MediaInfo) -> Double {
        var value = info.elapsed
        if isPlaying { value += Date().timeIntervalSince(info.timestamp) * (info.rate > 0 ? info.rate : 1) }
        return info.duration > 0 ? min(max(value, 0), info.duration) : max(value, 0)
    }

    /// Where INFO's track is at DATE, counting on from its last report while it plays.
    static func elapsed(_ info: MediaInfo, at date: Date) -> Double {
        var value = info.elapsed
        if info.isPlaying { value += date.timeIntervalSince(info.timestamp) * (info.rate > 0 ? info.rate : 1) }
        return info.duration > 0 ? min(max(value, 0), info.duration) : max(value, 0)
    }

    private func apply(_ info: MediaInfo?) {
        latest = info
        if let info {
            if info.isPlaying {
                remembered[info.bundleID] = info
            } else {
                remembered.removeValue(forKey: info.bundleID)
            }
        }
        lastBackgroundCheck = Date()
        refreshBackground()
    }

    /// macOS reports one now-playing app: whichever started playing last. Pause it, and macOS keeps reporting it
    /// paused rather than going back to an app that never stopped, such as a wallpaper with a soundtrack. So when the
    /// reported app is paused or gone, show another app that was playing when last heard from and is still
    /// making sound.
    private func backgroundPlayers() -> [MediaInfo] {
        // Forget apps that have quit.
        for (bundle, _) in remembered where NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty {
            remembered.removeValue(forKey: bundle)
        }
        let candidates = remembered.values.filter { $0.bundleID != latest?.bundleID }
        guard !candidates.isEmpty else { return [] }
        let playing = AudioActivity.playingBundleIDs()
        return candidates
            .filter { AudioActivity.isPlaying($0.bundleID, in: playing) }
            .sorted { $0.timestamp > $1.timestamp }
    }

    private func refreshBackground() {
        let background = backgroundPlayers()
        if latest?.isPlaying != true, let first = background.first {
            show(first, background: true)
        } else if let latest {
            show(latest, background: false)
        } else {
            shown = nil
            isBackground = false
            hasTrack = false
            isPlaying = false
        }
        updatePlayers(background)
    }

    /// The list for the Media tab: the app on screen first, then whatever else is playing, newest first, then the
    /// reported app if it is paused (it can still be resumed from there).
    private func updatePlayers(_ background: [MediaInfo]) {
        var entries = background.map { (info: $0, controllable: false) }
        if let latest { entries.append((latest, true)) }
        guard entries.count > 1 else {
            if !players.isEmpty { withAnimation(.smooth(duration: 0.3)) { players = [] } }
            playersSignature = ""
            return
        }
        let first = shown?.bundleID
        entries.sort { a, b in
            if (a.info.bundleID == first) != (b.info.bundleID == first) { return a.info.bundleID == first }
            if a.info.isPlaying != b.info.isPlaying { return a.info.isPlaying }
            return a.info.timestamp > b.info.timestamp
        }
        // A background player was playing when last heard from and still makes sound, so it counts as playing.
        let list = entries.map { entry -> NowPlayer in
            var info = entry.info
            if !entry.controllable { info.isPlaying = true }
            let app = appIdentity(info.bundleID)
            let art = artwork(for: info)
            return NowPlayer(info: info, name: app.name, icon: app.icon, artwork: art.image, tint: art.tint,
                             controllable: entry.controllable)
        }
        let signature = list.map { "\($0.id)|\($0.info.title)|\($0.info.artist)|\($0.isPlaying)|\($0.controllable)|\($0.info.elapsed)" }
            .joined(separator: "\n")
        guard signature != playersSignature else { return }
        playersSignature = signature
        withAnimation(.smooth(duration: 0.3)) { players = list }
    }

    private func artwork(for info: MediaInfo) -> (image: NSImage?, tint: Color) {
        let signature = "\(info.title)|\(info.artist)|\(info.artworkData?.count ?? 0)"
        if let cached = artworkCache[info.bundleID], cached.signature == signature { return (cached.image, cached.tint) }
        let image = info.artworkData.flatMap { NSImage(data: $0) }
        let tint = image?.vibrantColor ?? Color(white: 0.7)
        artworkCache[info.bundleID] = (signature, image, tint)
        return (image, tint)
    }

    private func appIdentity(_ bundleID: String) -> (name: String, icon: NSImage?) {
        if let cached = appCache[bundleID] { return cached }
        var identity: (name: String, icon: NSImage?) = (bundleID, nil)
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            identity = (FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""),
                        NSWorkspace.shared.icon(forFile: url.path))
        }
        appCache[bundleID] = identity
        return identity
    }

    private func show(_ info: MediaInfo, background: Bool) {
        shown = info
        if isBackground != background { withAnimation(.easeOut(duration: 0.2)) { isBackground = background } }
        hasTrack = true
        if background {
            isPlaying = true
        } else if Date() >= holdUntil {
            isPlaying = info.isPlaying
        }
        title = info.title
        artist = info.artist
        duration = info.duration
        position = livePosition(info)
        resolveSource(info.bundleID)

        let signature = "\(info.bundleID)|\(info.title)|\(info.artist)|\(info.artworkData?.count ?? 0)"
        if signature != artworkSignature {
            artworkSignature = signature
            artwork = info.artworkData.flatMap { NSImage(data: $0) }
        }
    }

    fileprivate func resolveSource(_ bundleID: String) {
        guard bundleID != sourceBundleID else { return }
        sourceBundleID = bundleID
        (sourceName, sourceIcon) = appIdentity(bundleID)
    }

    fileprivate func fallBackToScripts() {
        remote?.stop()
        remote = nil
        usingRemote = false
        latest = nil
        players = []
        startScripts()
    }
}

enum PlayerApp: String {
    case music = "Music"
    case spotify = "Spotify"

    var bundleID: String {
        switch self {
        case .music: return "com.apple.Music"
        case .spotify: return "com.spotify.client"
        }
    }

    var infoScript: String {
        let duration = self == .spotify ? "(((duration of t) / 1000) as integer)" : "((duration of t) as integer)"
        return """
        tell application "\(rawValue)"
            if player state is stopped then return "stopped|||||||||0|||0"
            set t to current track
            return (player state as string) & "|||" & (name of t) & "|||" & (artist of t) & "|||" & ((player position) as integer) & "|||" & \(duration)
        end tell
        """
    }
}

extension NowPlayingMonitor {
    fileprivate func startScripts() {
        guard scriptTimer == nil else { return }
        pollScripts()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.pollScripts() }
        RunLoop.main.add(timer, forMode: .common)
        scriptTimer = timer
    }

    fileprivate func stopScripts() {
        scriptTimer?.invalidate()
        scriptTimer = nil
    }

    fileprivate func scriptCommand(_ verb: String) {
        guard let app = scriptApp else { return }
        DispatchQueue.main.async { [weak self] in
            _ = self?.runScript("tell application \"\(app.rawValue)\" to \(verb)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.pollScripts() }
        }
    }

    private func isRunning(_ app: PlayerApp) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty
    }

    private func pollScripts() {
        var best: (PlayerApp, [String])?
        for app in [PlayerApp.music, .spotify] where isRunning(app) {
            guard let line = runScript(app.infoScript) else { continue }
            let parts = line.components(separatedBy: "|||")
            guard parts.count == 5, parts[0] != "stopped" else { continue }
            if best == nil || parts[0] == "playing" { best = (app, parts) }
        }

        guard let (app, parts) = best else {
            if hasTrack {
                hasTrack = false
                isPlaying = false
                scriptApp = nil
            }
            return
        }

        scriptApp = app
        hasTrack = true
        if Date() >= holdUntil { isPlaying = parts[0] == "playing" }
        title = parts[1]
        artist = parts[2]
        position = Double(parts[3]) ?? 0
        duration = Double(parts[4]) ?? 0
        resolveSource(app.bundleID)

        let key = "\(app.rawValue)|\(parts[1])|\(parts[2])"
        if key != scriptArtworkKey {
            scriptArtworkKey = key
            artwork = nil
            loadScriptArtwork(for: app)
        }
    }

    private func loadScriptArtwork(for app: PlayerApp) {
        switch app {
        case .music:
            let script = "tell application \"Music\" to return data of artwork 1 of current track"
            if let data = runScriptDescriptor(script)?.data, let image = NSImage(data: data) {
                artwork = image
            }
        case .spotify:
            guard let urlString = runScript("tell application \"Spotify\" to return artwork url of current track"),
                  let url = URL(string: urlString) else { return }
            let key = scriptArtworkKey
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data, let image = NSImage(data: data) else { return }
                DispatchQueue.main.async {
                    if self?.scriptArtworkKey == key { self?.artwork = image }
                }
            }.resume()
        }
    }

    private func runScriptDescriptor(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        return error == nil ? result : nil
    }

    fileprivate func runScript(_ source: String) -> String? {
        runScriptDescriptor(source)?.stringValue
    }
}
