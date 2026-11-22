import AppKit
import SwiftUI

/// Safari, closer to the island:
///
/// - Downloads in progress, as a Live Activity: Safari's own (its `.download` bundles keep how much has come and how
///   much there is), with the speed and the time left; Chrome's and Firefox's half-made files too, by how fast they
///   grow. Done, it gives way to the usual "Downloaded" banner.
/// - Now Playing, when the sound is Safari's: go to the tab that plays it, skip back or ahead ten seconds, change the
///   speed, or float the video in Picture in Picture. The last three run a line of JavaScript in the page, which
///   Safari only allows once "Allow JavaScript from Apple Events" is on (Develop menu); Isola says so if it isn't.
/// - The page in front: into the File Tray (as a link file to drag anywhere), onto the Reading List, its link
///   copied, or sent by AirDrop.
///
/// Safari web apps (Add to Dock) and Safari Technology Preview count as Safari throughout.
enum Safari {
    static let bundleIDs = ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]

    static func isSafari(_ bundleID: String?) -> Bool {
        guard let id = bundleID else { return false }
        return bundleIDs.contains(id) || id.hasPrefix("com.apple.Safari.WebApp")
    }

    /// The Safari to talk to: the one running (Technology Preview if only it is).
    static var appName: String {
        let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        if !running.contains("com.apple.Safari"), running.contains("com.apple.SafariTechnologyPreview") {
            return "Safari Technology Preview"
        }
        return "Safari"
    }

    static var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { isSafari($0.bundleIdentifier) }
    }

    // MARK: Scripting

    @discardableResult
    static func run(_ source: String) -> (String?, NSDictionary?) {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return (nil, nil) }
        let result = script.executeAndReturnError(&error)
        return (error == nil ? result.stringValue : nil, error)
    }

    private static func escaped(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// The page in the front window: (title, address).
    static func frontPage() -> (title: String, url: URL)? {
        guard isRunning else { return nil }
        let (out, _) = run("""
        tell application "\(appName)"
            if (count of windows) is 0 then return ""
            set t to current tab of front window
            return (name of t) & "|||" & (URL of t)
        end tell
        """)
        guard let parts = out?.components(separatedBy: "|||"), parts.count == 2, let url = URL(string: parts[1]),
              url.scheme?.hasPrefix("http") == true else { return nil }
        return (parts[0], url)
    }

    /// Brings forward the tab whose title holds TITLE (the playing tab's media title is usually in it), else the
    /// tab that is playing sound by its title's speaker... failing both, just Safari.
    static func showTab(matching title: String) {
        let needle = escaped(String(title.prefix(60)))
        let (out, _) = run("""
        tell application "\(appName)"
            repeat with w in windows
                repeat with t in tabs of w
                    if name of t contains "\(needle)" then
                        set current tab of w to t
                        set index of w to 1
                        activate
                        return "found"
                    end if
                end repeat
            end repeat
            activate
            return ""
        end tell
        """)
        if out != "found" {
            AppState.shared.showBanner(IslandBanner(symbol: "safari", tint: .blue, title: "Safari",
                                                    subtitle: "Couldn't tell which tab is playing"), for: 2.5)
        }
    }

    /// Runs JS in the tab whose title holds TITLE (or the front tab). Says what to switch on if Safari refuses.
    static func javascript(_ js: String, inTabMatching title: String?) {
        let needle = escaped(String((title ?? "").prefix(60)))
        let code = escaped(js)
        let (_, error) = run("""
        tell application "\(appName)"
            set target to missing value
            if "\(needle)" is not "" then
                repeat with w in windows
                    repeat with t in tabs of w
                        if name of t contains "\(needle)" then set target to t
                    end repeat
                end repeat
            end if
            if target is missing value then set target to current tab of front window
            do JavaScript "\(code)" in target
        end tell
        """)
        if let error {
            let message = (error[NSAppleScript.errorMessage] as? String) ?? ""
            let number = (error[NSAppleScript.errorNumber] as? Int) ?? 0
            let subtitle = number == -1743
                ? "Allow Isola to control Safari in System Settings, Privacy, Automation"
                : message.localizedCaseInsensitiveContains("JavaScript")
                    ? "Turn on Develop, Allow JavaScript from Apple Events in Safari"
                    : "Safari didn't do it"
            AppState.shared.showBanner(IslandBanner(symbol: "safari", tint: .orange, title: "Safari", subtitle: subtitle,
                                                    action: BannerAction(title: "How", symbol: "questionmark.circle") {
                if let url = URL(string: "https://support.apple.com/guide/safari/use-the-developer-tools-in-the-develop-menu-sfri20948/mac") {
                    NSWorkspace.shared.open(url)
                }
            }), for: 6)
        }
    }

    /// The first video or audio on the page, most likely the one playing.
    private static let media = "(Array.from(document.querySelectorAll('video,audio')).find(m=>!m.paused)||document.querySelector('video,audio'))"

    static func skip(_ seconds: Double, title: String?) {
        javascript("var m=\(media);if(m){m.currentTime=Math.max(0,m.currentTime+(\(seconds)));}", inTabMatching: title)
    }

    static func cycleSpeed(title: String?) {
        javascript("var m=\(media);if(m){var s=[1,1.25,1.5,2,.75];var i=s.indexOf(m.playbackRate);m.playbackRate=s[(i+1)%s.length];}",
                   inTabMatching: title)
    }

    static func pictureInPicture(title: String?) {
        javascript("""
        var v=Array.from(document.querySelectorAll('video')).find(m=>!m.paused)||document.querySelector('video');
        if(v){if(v.webkitSupportsPresentationMode&&v.webkitSupportsPresentationMode('picture-in-picture')){v.webkitSetPresentationMode(v.webkitPresentationMode==='picture-in-picture'?'inline':'picture-in-picture');}else if(v.requestPictureInPicture){v.requestPictureInPicture();}}
        """, inTabMatching: title)
    }

    // MARK: The page in front

    static func pageToTray() {
        guard let page = frontPage() else { return noPage() }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Isola Links", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = page.title.isEmpty ? (page.url.host ?? "Link") : page.title
        let safe = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").prefix(80)
        let file = folder.appendingPathComponent("\(safe).webloc")
        let plist: [String: Any] = ["URL": page.url.absoluteString]
        if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
            try? data.write(to: file)
            AppState.shared.tray.add([file])
            AppState.shared.showBanner(IslandBanner(symbol: "link", tint: .blue, title: String(name.prefix(60)),
                                                    subtitle: "In the tray"), for: 2.5)
        }
    }

    static func addToReadingList() {
        guard let page = frontPage() else { return noPage() }
        let (_, error) = run("tell application \"\(appName)\" to add reading list item \"\(escaped(page.url.absoluteString))\" with title \"\(escaped(page.title))\"")
        AppState.shared.showBanner(IslandBanner(symbol: error == nil ? "eyeglasses" : "exclamationmark.triangle",
                                                tint: error == nil ? .blue : .orange,
                                                title: error == nil ? "On your Reading List" : "Couldn't add it",
                                                subtitle: String(page.title.prefix(60))), for: 2.5)
    }

    static func copyLink() {
        guard let page = frontPage() else { return noPage() }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([page.url as NSURL])
        pb.setString(page.url.absoluteString, forType: .string)
        AppState.shared.showBanner(IslandBanner(symbol: "link", tint: .blue, title: "Link copied",
                                                subtitle: page.url.host ?? ""), for: 2)
    }

    static func airDrop() {
        guard let page = frontPage() else { return noPage() }
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: [page.url]) else {
            AppState.shared.showBanner(IslandBanner(symbol: "airplayaudio", tint: .orange, title: "AirDrop",
                                                    subtitle: "Not available right now"), for: 2.5)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: [page.url])
    }

    private static func noPage() {
        AppState.shared.showBanner(IslandBanner(symbol: "safari", tint: .gray, title: "Safari",
                                                subtitle: isRunning ? "No page open" : "Safari isn't open"), for: 2.5)
    }
}

// MARK: - Downloads in progress

/// Watches the downloads folder for files still arriving and shows them as one Live Activity.
final class DownloadProgress {
    static let shared = DownloadProgress()

    private var timer: Timer?
    private var last: [String: (bytes: Double, at: Date)] = [:]
    private var speed: Double = 0
    private let id = "isola.downloads"
    private var showing = false

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        end()
    }

    /// Safari's chosen folder, if it has one, else ~/Downloads.
    private var folder: URL {
        if let path = UserDefaults(suiteName: "com.apple.Safari")?.string(forKey: "DownloadsPath"), !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }

    private struct Item {
        var name: String
        var bytes: Double
        var total: Double?
    }

    private func items() -> [Item] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { return [] }
        var out: [Item] = []
        for name in names where !name.hasPrefix(".") {
            let url = folder.appendingPathComponent(name)
            let ext = url.pathExtension.lowercased()
            if ext == "download" {
                // Safari: a bundle with the file inside and an Info.plist saying how far along it is
                let info = url.appendingPathComponent("Info.plist")
                let plist = (try? Data(contentsOf: info)).flatMap {
                    try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any]
                }
                let so = (plist?["DownloadEntryProgressBytesSoFar"] as? NSNumber)?.doubleValue
                let total = (plist?["DownloadEntryProgressTotalToLoad"] as? NSNumber)?.doubleValue
                let display = (name as NSString).deletingPathExtension
                out.append(Item(name: display, bytes: so ?? size(of: url), total: (total ?? 0) > 0 ? total : nil))
            } else if ["crdownload", "part", "partial"].contains(ext) {
                // Chrome, Firefox, Edge: a file that grows; how big it will be isn't written down
                var display = (name as NSString).deletingPathExtension
                if display.hasPrefix("Unconfirmed ") { display = "Download" }
                out.append(Item(name: display, bytes: size(of: url), total: nil))
            }
        }
        return out
    }

    private func size(of url: URL) -> Double {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            return Double((try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0)
        }
        var total: Double = 0
        if let e = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let f as URL in e {
                total += Double((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
        return total
    }

    private func tick() {
        guard UserDefaults.standard.bool(forKey: Prefs.liveDownloads) else { return end() }
        let list = items()
        guard !list.isEmpty else { return end() }
        let now = Date()
        var rate: Double = 0
        for item in list {
            if let prev = last[item.name] {
                let dt = now.timeIntervalSince(prev.at)
                if dt > 0 { rate += max(0, item.bytes - prev.bytes) / dt }
            }
            last[item.name] = (item.bytes, now)
        }
        last = last.filter { key, _ in list.contains { $0.name == key } }
        speed = speed == 0 ? rate : speed * 0.6 + rate * 0.4
        let bytes = list.reduce(0) { $0 + $1.bytes }
        let known = list.allSatisfy { $0.total != nil }
        let total = known ? list.reduce(0) { $0 + ($1.total ?? 0) } : nil
        var parts: [String] = []
        if let total {
            parts.append("\(Self.bytes(bytes)) of \(Self.bytes(total))")
        } else {
            parts.append(Self.bytes(bytes))
        }
        if speed > 1024 { parts.append("\(Self.bytes(speed))/s") }
        if let total, speed > 1024 {
            let left = (total - bytes) / speed
            parts.append(left < 60 ? "\(Int(left.rounded())) s left" : "\(Int((left / 60).rounded())) min left")
        }
        var activity = LiveActivity(id: id, symbol: "arrow.down.circle.fill", tint: .blue,
                                    title: list.count == 1 ? list[0].name : "\(list.count) downloads",
                                    subtitle: parts.joined(separator: " · "))
        if let total, total > 0 {
            activity.progress = min(1, bytes / total)
        } else {
            activity.trailing = Self.bytes(bytes)
        }
        activity.priority = 2
        AppState.shared.setActivity(activity, peek: !showing)
        showing = true
    }

    private func end() {
        guard showing else { return }
        showing = false
        speed = 0
        last = [:]
        AppState.shared.endActivity(id)
    }

    static func bytes(_ b: Double) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false
        return f.string(fromByteCount: Int64(b))
    }
}

// MARK: - Controls on the Now Playing card

/// The row under Now Playing when the sound comes from Safari.
struct SafariMediaRow: View {
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            chip("safari", "Tab") { Safari.showTab(matching: title) }
            chip("gobackward.10", "") { Safari.skip(-10, title: title) }
            chip("goforward.10", "") { Safari.skip(10, title: title) }
            chip("speedometer", "Speed") { Safari.cycleSpeed(title: title) }
            chip("pip.enter", "PiP") { Safari.pictureInPicture(title: title) }
        }
    }

    private func chip(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 10.5, weight: .semibold))
                if !label.isEmpty { Text(label).font(.system(size: 10, weight: .semibold)) }
            }
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
}
