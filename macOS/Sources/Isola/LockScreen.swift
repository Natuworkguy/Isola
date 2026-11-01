import AppKit
import Combine
import UserNotifications

/// Live Activities from other apps (Flash's, through flash-isola) on the lock screen. The Mac lets no app draw
/// there, but notifications show, so while the screen is locked each such activity is one quiet notification, updated
/// in place as it goes: what it is doing, the step it is on, how far along. When it ends, its notification says so
/// and stays; unlocking clears them all, since the island is back.
final class LockScreen: NSObject, ObservableObject {
    static let shared = LockScreen()

    private static let prefix = "isola.lock."
    /// Updates come no closer together than this, unless the step changed or it ended.
    private static let minimumGap: TimeInterval = 6

    private var locked = false
    private var watching: AnyCancellable?
    private var shown: [String: (body: String, step: String, at: Date, title: String)] = [:]
    private var asked = false
    /// Whether notifications are allowed, as Settings shows it: nil until known.
    @Published private(set) var allowed: Bool?
    /// What happened last, as Settings shows it: the lock seen, the notification shown, or why macOS refused it.
    @Published private(set) var lastSeen = ""
    /// Whether Try it is waiting for the Mac to be locked.
    @Published private(set) var trying = false

    private var enabled: Bool { UserDefaults.standard.bool(forKey: Prefs.lockScreen) }
    private var center: UNUserNotificationCenter { .current() }

    func start() {
        // Notifications need a real app bundle; run from `swift run` there is none.
        guard Bundle.main.bundleIdentifier != nil else { return }
        // Shown even while Isola is the app in front, as when its Settings are open: macOS keeps an app's own
        // notifications to itself then, unless it says otherwise.
        center.delegate = self
        let system = DistributedNotificationCenter.default()
        system.addObserver(self, selector: #selector(didLock),
                           name: .init("com.apple.screenIsLocked"), object: nil)
        system.addObserver(self, selector: #selector(didUnlock),
                           name: .init("com.apple.screenIsUnlocked"), object: nil)
        watching = AppState.shared.$activities
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.changed($0) }
        // Asked as Isola starts, with the Mac in use: not when the first activity comes, which may be just before
        // the screen locks, with the question waiting unseen behind it.
        if enabled { askOnce() } else { check() }
    }

    /// What the Mac lets Isola do now, for Settings.
    func check() {
        center.getNotificationSettings { settings in
            let ok = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            DispatchQueue.main.async { self.allowed = ok }
        }
    }

    /// A sample, a few seconds from now: time to lock the Mac and see it there, as Flash's progress would be.
    func tryIt() {
        trying = true
        askOnce(force: true) { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                guard let self else { return }
                self.trying = false
                self.post(id: "sample", title: "Flash", body: "Step 2 of 4: Run the tests", first: true)
            }
        }
    }

    /// System Settings, at Isola's notifications.
    func openSystemSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)")
            ?? URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!
        NSWorkspace.shared.open(url)
    }

    @objc private func didLock() {
        locked = true
        let count = AppState.shared.activities.filter { ActivityLink.ids.contains($0.id) }.count
        lastSeen = "Saw the Mac lock at \(Self.time()), with \(count) activit\(count == 1 ? "y" : "ies") from apps."
        changed(AppState.shared.activities)
    }

    private static func time() -> String {
        Date().formatted(date: .omitted, time: .standard)
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
            post(id: activity.id, title: title, body: body, first: shown[activity.id] == nil)
            shown[activity.id] = (body, step, Date(), title)
        }
        // Ended while locked: its notification says it finished, and stays until unlock.
        for id in shown.keys where !linked.contains(where: { $0.id == id }) {
            if let last = shown[id], last.body != Self.finished {
                post(id: id, title: last.title, body: Self.finished, first: false)
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

    /// FIRST is its first notification: shown as notifications usually are, since a quiet ("passive") one may not
    /// show on the lock screen at all. Its updates replace it in place, quietly.
    private func post(id: String, title: String, body: String, first: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.threadIdentifier = "isola.activities"
        content.sound = nil
        content.interruptionLevel = first ? .active : .passive
        let request = UNNotificationRequest(identifier: Self.prefix + id, content: content, trigger: nil)
        center.add(request) { error in
            DispatchQueue.main.async {
                let when = Self.time()
                if let error {
                    self.lastSeen = "macOS refused to show \"\(title)\" at \(when): \(error.localizedDescription)"
                } else {
                    self.lastSeen = "Showed \"\(title)\" at \(when)\(self.locked ? ", while locked" : "")."
                }
            }
        }
    }

    private func askOnce(force: Bool = false, then: (() -> Void)? = nil) {
        guard force || !asked else { return }
        asked = true
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else {
                self.check()
                DispatchQueue.main.async { then?() }
                return
            }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in
                self.check()
                DispatchQueue.main.async { then?() }
            }
        }
    }
}

extension LockScreen: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}
