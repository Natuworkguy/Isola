import AppKit
import SwiftUI

/// `isola://notify` links: any app or script can make the island show a short banner, for example
///
///     open -g "isola://notify?title=Build%20done&text=All%20tests%20pass&symbol=checkmark.circle.fill&color=green"
///
/// | Parameter  | Meaning |
/// | ---------- | ------- |
/// | `title`    | First line, bold. |
/// | `text`     | Second line. With no title it becomes the only line. |
/// | `symbol`   | An SF Symbol name. Default `bell.fill`. |
/// | `color`    | A colour name (green, red, orange…) or hex like `ff9500`. Default mint. |
/// | `duration` | Seconds on screen, 1 to 30. Default 4. |
/// | `sound`    | A macOS sound name, such as Glass or Ping. Default none. |
///
/// Since anything can open the link, it only ever shows text: no buttons, no links, nothing it runs.
enum NotifyLink {
    struct Request: Equatable {
        let banner: IslandBanner
        let seconds: TimeInterval
        let sound: String?
    }

    static let maxTitle = 80
    static let maxText = 200

    private static let colors: [String: Color] = [
        "red": .red, "orange": .orange, "yellow": .yellow, "green": .green, "mint": .mint, "teal": .teal,
        "cyan": .cyan, "blue": .blue, "indigo": .indigo, "purple": .purple, "pink": .pink, "brown": .brown,
        "gray": .gray, "grey": .gray,
    ]

    static func handle(_ url: URL) {
        guard UserDefaults.standard.bool(forKey: Prefs.notifyLinks), let request = parse(url) else { return }
        AppState.shared.showBanner(request.banner, for: request.seconds)
        if let sound = request.sound { NSSound(named: NSSound.Name(sound))?.play() }
    }

    static func parse(_ url: URL) -> Request? {
        guard url.scheme?.lowercased() == "isola", url.host?.lowercased() == "notify" else { return nil }
        let values = query(url)

        let title = clean(values["title"], maxTitle)
        let text = clean(values["text"] ?? values["message"], maxText)
        guard !title.isEmpty || !text.isEmpty else { return nil }

        var symbol = "bell.fill"
        if let wanted = values["symbol"], wanted.count <= 64,
           NSImage(systemSymbolName: wanted, accessibilityDescription: nil) != nil {
            symbol = wanted
        }

        let seconds = min(max(Double(values["duration"] ?? "") ?? 4, 1), 30)

        var sound: String?
        if let name = values["sound"], !name.isEmpty, name.count <= 32,
           name.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) {
            sound = name
        }

        return Request(
            banner: IslandBanner(
                symbol: symbol,
                tint: color(values["color"]) ?? .mint,
                title: title.isEmpty ? text : title,
                subtitle: title.isEmpty ? "" : text
            ),
            seconds: seconds,
            sound: sound
        )
    }

    /// A link's parameters by lowercased name, the first of each, decoded.
    static func query(_ url: URL) -> [String: String] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [:] }
        var values: [String: String] = [:]
        for item in components.percentEncodedQueryItems ?? [] {
            let key = item.name.lowercased()
            guard values[key] == nil else { continue }
            // Accept form encoding too, where a space is written as +.
            let raw = (item.value ?? "").replacingOccurrences(of: "+", with: " ")
            values[key] = raw.removingPercentEncoding ?? raw
        }
        return values
    }

    static func symbol(_ value: String?) -> String? {
        guard let value, value.count <= 64, NSImage(systemSymbolName: value, accessibilityDescription: nil) != nil else { return nil }
        return value
    }

    static func clean(_ value: String?, _ limit: Int) -> String {
        let words = (value ?? "").split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        return String(words.joined(separator: " ").prefix(limit))
    }

    static func color(_ value: String?) -> Color? {
        guard let value = value?.lowercased().trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        if let named = colors[value] { return named }
        let hex = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard hex.count == 6, let number = UInt32(hex, radix: 16) else { return nil }
        return Color(
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255
        )
    }
}

/// `isola://activity` links: any app or script can show its own Live Activity, a checklist that updates in place,
/// for example
///
///     open -g "isola://activity?id=build&title=Build&subtitle=Release&symbol=hammer.fill&color=orange&steps=done:Fetch|active:Compile|todo:Test"
///     open -g "isola://activity/end?id=build"
///
/// | Parameter   | Meaning |
/// | ----------- | ------- |
/// | `id`        | Required: letters, digits, `.`, `-` and `_`, up to 64. The same id updates the activity in place. |
/// | `title`     | The card's first words, bold. |
/// | `subtitle`  | After a dot, in the activity's colour. |
/// | `symbol`    | An SF Symbol name. Default `sparkles`. |
/// | `color`     | A colour name or hex, as for notify. Default mint. |
/// | `steps`     | Up to 12, separated by `|`, each `done:`, `active:`, `todo:` or `failed:` and its text. |
/// | `lines`     | A conversation as it goes: up to 6, separated by `|`, each a speaker, `:`, and what they said. |
/// | `progress`  | 0 to 1: a ring in the ears, a bar on the card. Empty clears it. |
/// | `trailing`  | Up to 8 characters for the right ear. |
/// | `countdown` | Seconds to count down from in the ears. `elapsed` counts up from that many instead. Empty clears. |
/// | `priority`  | `low` lets music keep the ears while this runs. |
/// | `mic`       | `talking`, `listening`, `on` or `off`: it is using the microphone, in place of Isola's own dot and banner. Listening and talking show live bars for its icon. |
/// | `peek`      | `1` shows its card now, `0` keeps it in the ears. By default the card shows when it starts and when its steps or lines change. |
///
/// Only the parameters given change. An activity ends after two hours without an update, and at most eight from
/// links run at once. Like notify links, an activity only ever shows text.
enum ActivityLink {
    static let maxActivities = 8
    private static var updated: [String: Date] = [:]
    private static var sweeper: Timer?

    static func handle(_ url: URL) {
        guard UserDefaults.standard.bool(forKey: Prefs.activityLinks) else { return }
        guard url.scheme?.lowercased() == "isola", url.host?.lowercased() == "activity" else { return }
        let values = NotifyLink.query(url)
        guard let id = values["id"], (1...64).contains(id.count), !id.lowercased().hasPrefix("isola."),
              id.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || "._-".unicodeScalars.contains($0) })
        else { return }
        let state = AppState.shared
        if url.path.lowercased().hasPrefix("/end") {
            updated[id] = nil
            state.endActivity(id)
            return
        }
        let existing = state.activity(id)
        guard existing != nil || updated.count < maxActivities else { return }
        var activity = existing ?? LiveActivity(id: id, symbol: "sparkles", tint: .mint, title: "")
        apply(values, to: &activity)
        let stepsChanged = existing?.steps != activity.steps
        let linesChanged = existing?.lines != activity.lines
        let peek = values["peek"] == "1"
            || (values["peek"] != "0" && (existing == nil || (stepsChanged && !activity.steps.isEmpty)
                || (linesChanged && !activity.lines.isEmpty)))
        updated[id] = Date()
        state.setActivity(activity, peek: peek)
        startSweeping()
    }

    static func apply(_ values: [String: String], to activity: inout LiveActivity) {
        if let title = values["title"] { activity.title = NotifyLink.clean(title, NotifyLink.maxTitle) }
        if let subtitle = values["subtitle"] { activity.subtitle = NotifyLink.clean(subtitle, NotifyLink.maxTitle) }
        if let symbol = NotifyLink.symbol(values["symbol"]) { activity.symbol = symbol }
        if let tint = NotifyLink.color(values["color"]) { activity.tint = tint }
        if let trailing = values["trailing"] { activity.trailing = NotifyLink.clean(trailing, 8) }
        if let raw = values["steps"] { activity.steps = steps(raw) }
        if let raw = values["lines"] { activity.lines = lines(raw) }
        if let raw = values["progress"] { activity.progress = Double(raw).map { min(max($0, 0), 1) } }
        if let raw = values["countdown"] {
            activity.endsAt = Double(raw).map { Date().addingTimeInterval(min(max($0, 0), 86_400)) }
        }
        if let raw = values["elapsed"] {
            activity.since = Double(raw).map { Date().addingTimeInterval(-min(max($0, 0), 86_400)) }
        }
        if let priority = values["priority"] { activity.priority = priority.lowercased() == "low" ? 1 : 2 }
        if let raw = values["mic"] {
            let word = raw.lowercased()
            activity.mic = LiveActivity.Mic(rawValue: word) ?? (word == "1" ? .on : .off)
        }
    }

    static func steps(_ raw: String) -> [LiveActivity.Step] {
        raw.split(separator: "|").prefix(12).compactMap { part in
            var text = String(part)
            var state = LiveActivity.Step.State.pending
            if let colon = text.firstIndex(of: ":") {
                let word = text[..<colon].lowercased().trimmingCharacters(in: .whitespaces)
                let known: [String: LiveActivity.Step.State] = [
                    "done": .done, "active": .active, "now": .active, "todo": .pending, "pending": .pending,
                    "failed": .failed, "error": .failed,
                ]
                if let found = known[word] {
                    state = found
                    text = String(text[text.index(after: colon)...])
                }
            }
            let cleaned = NotifyLink.clean(text, 100)
            return cleaned.isEmpty ? nil : LiveActivity.Step(text: cleaned, state: state)
        }
    }

    /// A conversation: each part a speaker, a colon and what they said. The newest six are kept.
    static func lines(_ raw: String) -> [LiveActivity.Line] {
        let parsed: [LiveActivity.Line] = raw.split(separator: "|").compactMap { part in
            let text = String(part)
            guard let colon = text.firstIndex(of: ":") else {
                let said = NotifyLink.clean(text, 200)
                return said.isEmpty ? nil : LiveActivity.Line(speaker: "", text: said)
            }
            let speaker = NotifyLink.clean(String(text[..<colon]), 24)
            let said = NotifyLink.clean(String(text[text.index(after: colon)...]), 200)
            return said.isEmpty ? nil : LiveActivity.Line(speaker: speaker, text: said)
        }
        return Array(parsed.suffix(6))
    }

    /// Ends activities from links that have not been updated for two hours: their app has probably gone.
    private static func startSweeping() {
        guard sweeper == nil else { return }
        let timer = Timer(timeInterval: 60, repeats: true) { _ in
            let stale = updated.filter { Date().timeIntervalSince($0.value) > 2 * 3600 }.map(\.key)
            for id in stale {
                updated[id] = nil
                AppState.shared.endActivity(id)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        sweeper = timer
    }
}

/// What the island grows to show for a moment when a notification arrives. A ringing banner (a timer or alarm going
/// off) shakes its bell and glows until it is answered.
struct BannerView: View {
    let banner: IslandBanner
    let topInset: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: topInset)
            HStack(spacing: 12) {
                icon
                VStack(alignment: .leading, spacing: 1) {
                    Text(banner.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if !banner.subtitle.isEmpty {
                        Text(banner.subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                    }
                }
                if banner.action != nil || banner.secondAction != nil {
                    HStack(spacing: 6) {
                        if let second = banner.secondAction {
                            button(second, primary: false)
                        }
                        if let action = banner.action {
                            button(action, primary: true)
                        }
                    }
                    .padding(.leading, 6)
                }
            }
            .padding(.horizontal, 18)
            // Centred both ways in the space below the notch, or in the whole banner without one.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder private var icon: some View {
        let circle = Image(systemName: banner.symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(Circle().fill(banner.tint.gradient))
        if banner.ringing {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                // Two quick shakes, then a pause, like a bell.
                let phase = t.truncatingRemainder(dividingBy: 1.2)
                let angle = phase < 0.5 ? sin(phase * .pi * 8) * 18 * (1 - phase * 2) : 0
                circle
                    .rotationEffect(.degrees(angle))
                    .shadow(color: banner.tint.opacity(0.55 + 0.35 * sin(t * 4)), radius: 10)
            }
        } else {
            circle.shadow(color: banner.tint.opacity(0.6), radius: 8)
        }
    }

    private func button(_ action: BannerAction, primary: Bool) -> some View {
        Button {
            action.perform()
            AppState.shared.dismissBanner()
        } label: {
            Label(action.title, systemImage: action.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(primary ? Color.black : Color.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(primary ? Color.white : Color.white.opacity(0.18)))
        }
        .buttonStyle(.plain)
    }
}
