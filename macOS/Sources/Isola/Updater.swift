import AppKit
import SwiftUI

/// Knowing when there's a newer Isola: once a day (and from Settings) it asks GitHub for the latest release, and if
/// it's newer than this one, says so in the island with a button to get it.
final class Updater: ObservableObject {
    static let shared = Updater()
    private static let latest = URL(string: "https://api.github.com/repos/Natuworkguy/Isola/releases/latest")!

    @Published private(set) var status = ""
    @Published private(set) var newer: (version: String, page: URL)?
    private var timer: Timer?

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.check(quietly: true) }
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in
            self?.check(quietly: true)
        }
    }

    /// QUIETLY: only a newer version is worth a banner; asked from Settings, the answer shows there either way.
    func check(quietly: Bool = false) {
        guard !quietly || UserDefaults.standard.bool(forKey: Prefs.checkUpdates) else { return }
        status = "Checking…"
        var request = URLRequest(url: Self.latest, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            let release = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            DispatchQueue.main.async {
                guard let self else { return }
                guard let tag = release?["tag_name"] as? String,
                      let page = (release?["html_url"] as? String).flatMap(URL.init(string:)) else {
                    self.status = "Couldn't reach GitHub to check."
                    return
                }
                let found = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                if Self.isNewer(found, than: Self.version) {
                    self.newer = (found, page)
                    self.status = "Isola \(found) is out."
                    var banner = IslandBanner(symbol: "arrow.down.circle.fill", tint: .blue,
                                              title: "Isola \(found) is out", subtitle: "You have \(Self.version)")
                    banner.action = BannerAction(title: "Get it", symbol: "arrow.down") { NSWorkspace.shared.open(page) }
                    AppState.shared.showBanner(banner, for: 8)
                } else {
                    self.newer = nil
                    self.status = "Isola \(Self.version) is the latest."
                }
            }
        }.resume()
    }

    /// Version numbers compared part by part: 1.10.0 is newer than 1.9.2.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }
}
