import Combine
import Foundation
import SwiftUI

/// The words of the song playing, line by line with their times, so the line being sung shows under the title. From
/// LRCLIB, a free, open lyrics library: Isola sends it the song's title, artist and length, and nothing else. Off
/// until it is turned on in Settings, Island, since it goes online.
final class Lyrics: ObservableObject {
    static let shared = Lyrics()

    struct Line: Equatable {
        let time: Double
        let text: String
    }

    /// The line being sung now, or "" between lines, before the first, or when the song has no timed lyrics.
    @Published private(set) var current = ""
    @Published private(set) var next = ""
    @Published private(set) var lines: [Line] = []

    private var key = ""
    private var cache: [String: [Line]] = [:]
    private var task: URLSessionDataTask?
    private var watch: AnyCancellable?

    /// Follows MONITOR: fetches the words when the song changes, and moves the line along as it plays.
    func follow(_ monitor: NowPlayingMonitor) {
        guard watch == nil else { return }
        watch = Publishers.CombineLatest4(monitor.$title, monitor.$artist, monitor.$duration, monitor.$position)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] title, artist, duration, position in
                self?.update(title: title, artist: artist, duration: duration, position: position)
            }
    }

    private func update(title: String, artist: String, duration: Double, position: Double) {
        guard UserDefaults.standard.bool(forKey: Prefs.lyrics), !title.isEmpty else {
            if !lines.isEmpty || !current.isEmpty { clear() }
            return
        }
        let wanted = "\(artist)|\(title)"
        if wanted != key {
            key = wanted
            clear()
            if let known = cache[wanted] { lines = known } else { fetch(title: title, artist: artist, duration: duration, key: wanted) }
        }
        place(at: position)
    }

    private func clear() {
        task?.cancel()
        lines = []
        if !current.isEmpty { withAnimation(.easeOut(duration: 0.25)) { current = "" } }
        next = ""
    }

    /// Picks the line for POSITION: the last one that has started, a quarter of a second early so it lands with the
    /// voice rather than after it.
    private func place(at position: Double) {
        guard !lines.isEmpty else { return }
        let at = position + 0.25
        let index = lines.lastIndex { $0.time <= at }
        let line = index.map { lines[$0].text } ?? ""
        let after = index.map { $0 + 1 < lines.count ? lines[$0 + 1].text : "" } ?? lines[0].text
        if line != current { withAnimation(.smooth(duration: 0.35)) { current = line } }
        if after != next { next = after }
    }

    private func fetch(title: String, artist: String, duration: Double, key: String) {
        var parts = URLComponents(string: "https://lrclib.net/api/get")!
        parts.queryItems = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)]
        if duration > 0 { parts.queryItems?.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }
        guard let url = parts.url else { return }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Isola (https://github.com/Natuworkguy/Isola)", forHTTPHeaderField: "User-Agent")
        task = URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            let found = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                .flatMap { $0["syncedLyrics"] as? String }
                .map(Self.parse) ?? []
            DispatchQueue.main.async {
                guard let self, self.key == key else { return }
                self.cache[key] = found
                self.lines = found
            }
        }
        task?.resume()
    }

    /// Timed lyrics, "[01:23.45] the words", one line each. Lines with several times are sung more than once.
    static func parse(_ text: String) -> [Line] {
        var lines: [Line] = []
        let stamp = try? NSRegularExpression(pattern: #"\[(\d+):(\d+(?:\.\d+)?)\]"#)
        for raw in text.split(whereSeparator: \.isNewline) {
            let row = String(raw)
            let range = NSRange(row.startIndex..., in: row)
            let matches = stamp?.matches(in: row, range: range) ?? []
            guard let last = matches.last, let end = Range(last.range, in: row) else { continue }
            let words = row[end.upperBound...].trimmingCharacters(in: .whitespaces)
            for match in matches {
                guard let m = Range(match.range(at: 1), in: row), let s = Range(match.range(at: 2), in: row),
                      let minutes = Double(row[m]), let seconds = Double(row[s]) else { continue }
                lines.append(Line(time: minutes * 60 + seconds, text: words))
            }
        }
        return lines.sorted { $0.time < $1.time }
    }
}

/// The line being sung, under the artist: it fades and rises into place as each line starts.
struct LyricLine: View {
    @ObservedObject var lyrics = Lyrics.shared
    var size: CGFloat = 12

    var body: some View {
        if !lyrics.lines.isEmpty {
            Text(lyrics.current.isEmpty ? "♪" : lyrics.current)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .id(lyrics.current)
                .transition(.asymmetric(insertion: .offset(y: 8).combined(with: .opacity),
                                        removal: .offset(y: -8).combined(with: .opacity)))
                .help(lyrics.next.isEmpty ? lyrics.current : "Next: \(lyrics.next)")
        }
    }
}
