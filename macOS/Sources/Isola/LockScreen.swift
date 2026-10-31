import AppKit
import Combine
import UserNotifications

/// Live Activities from other apps (Flash's, through flash-isola) on the lock screen. The Mac lets no app draw
/// there, but notifications show, so while the screen is locked each such activity is one quiet notification, updated
/// in place as it goes: what it is doing, the step it is on, how far along. When it ends, its notification says so
/// and stays; unlocking clears them all, since the island is back.
final class LockScreen: NSObject {
    static let shared = LockScreen()

    private static let prefix = "isola.lock."
    /// Updates come no closer together than this, unless the step changed or it ended.
    private static let minimumGap: TimeInterval = 6

    private var locked = false
    private var watching: AnyCancellable?
    private var shown: [String: (body: String, step: String, at: Date, title: String)] = [:]
    private var asked = false

    private var enabled: Bool { UserDefaults.standard.bool(forKey: Prefs.lockScreen) }
    private var center: UNUserNotificationCenter { .current() }

    func start() {
        // Notifications need a real app bundle; run from `swift run` there is none.
        guard Bundle.main.bundleIdentifier != nil else { return }
        let system = DistributedNotificationCenter.default()
        system.addObserver(self, selector: #selector(didLock),
                           name: .init("com.apple.screenIsLocked"), object: nil)
        system.addObserver(self, selector: #selector(didUnlock),
                           name: .init("com.apple.screenIsUnlocked"), object: nil)
        watching = AppState.shared.$activities
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.changed($0) }
    }

    @objc private func didLock() {
        locked = true
        changed(AppState.shared.activities)
    }

    @objc private func didUnlock() {
        locked = false
        let ids = shown.keys.map { Self.prefix + $0 }
        center.removeDeliveredNotifications(withIdentifiers: ids)
        center.getDeliveredNotifications { delivered in
            let ours = delivered.map(\.request.identifier).filter { $0.hasPrefix(Self.prefix) }
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ours)
        }
        shown = [:]
    }

    private func changed(_ activities: [LiveActivity]) {
        guard enabled else { return }
        let linked = activities.filter { ActivityLink.ids.contains($0.id) }
        // Asked once, while the Mac is in use: never with a prompt waiting behind the lock screen.
        if !locked {
            if !linked.isEmpty { askOnce() }
            return
        }
        for activity in linked {
            let step = activity.steps.first { $0.state == .active }?.text ?? ""
            let body = Self.body(activity)
            if let last = shown[activity.id] {
                if last.body == body { continue }
                if last.step == step && Date().timeIntervalSince(last.at) < Self.minimumGap { continue }
            }
            let title = activity.title.isEmpty ? "Live Activity" : activity.title
            post(id: activity.id, title: title, body: body)
            shown[activity.id] = (body, step, Date(), title)
        }
        // Ended while locked: its notification says it finished, and stays until unlock.
        for id in shown.keys where !linked.contains(where: { $0.id == id }) {
            if let last = shown[id], last.body != Self.finished {
                post(id: id, title: last.title, body: Self.finished)
                shown[id] = (Self.finished, "", Date(), last.title)
            }
        }
    }

    private static let finished = "Finished."

    /// What a notification says of ACTIVITY: its subtitle, then the step it is on and how many are done, or the
    /// latest of a conversation.
    static func body(_ activity: LiveActivity) -> String {
        var parts: [String] = []
        if !activity.subtitle.isEmpty { parts.append(activity.subtitle) }
        if !activity.steps.isEmpty {
            let done = activity.steps.filter { $0.state == .done }.count
            let failed = activity.steps.first { $0.state == .failed }
            if let failed {
                parts.append("Stuck at: \(failed.text)")
            } else if let now = activity.steps.first(where: { $0.state == .active }) {
                parts.append("Step \(done + 1) of \(activity.steps.count): \(now.text)")
            } else {
                parts.append("\(done) of \(activity.steps.count) done")
            }
        } else if let line = activity.lines.last {
            parts.append(line.text)
        } else if let progress = activity.progress {
            parts.append("\(Int((progress * 100).rounded()))%")
        } else if !activity.trailing.isEmpty {
            parts.append(activity.trailing)
        }
        return parts.isEmpty ? "Working" : parts.joined(separator: "\n")
    }

    private func post(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.threadIdentifier = "isola.activities"
        content.sound = nil
        content.interruptionLevel = .passive
        let request = UNNotificationRequest(identifier: Self.prefix + id, content: content, trigger: nil)
        center.add(request)
    }

    private func askOnce() {
        guard !asked else { return }
        asked = true
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
        }
    }
}
