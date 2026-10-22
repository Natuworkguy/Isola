import AppKit
import ApplicationServices
import Carbon
import CoreAudio
import CoreMediaIO
import EventKit
import Network
import SwiftUI

/// More moments worth a glance, each switched on and off in Settings: the camera and microphone in use, downloads,
/// screenshots, the network, displays, Caps Lock, the keyboard layout, the next meeting, low storage, Focus, and
/// alarms and timers from the Clock app.
final class SystemActivities {
    private var started = false
    private var timer: Timer?
    private var ticks = 0
    private let defaults = UserDefaults.standard
    private let clockAlerts = ClockAlerts()

    func start() {
        guard !started else { return }
        started = true
        startNetwork()
        startDisplays()
        startKeyboard()
        startFolderWatchers()
        clockAlerts.start()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.startFolderWatchers() }
    }

    private func on(_ key: String) -> Bool { defaults.bool(forKey: key) }

    private func banner(_ symbol: String, _ tint: Color, _ title: String, _ subtitle: String,
                        seconds: TimeInterval = 3, action: BannerAction? = nil) {
        AppState.shared.showBanner(
            IslandBanner(symbol: symbol, tint: tint, title: title, subtitle: subtitle, action: action), for: seconds)
    }

    /// Caps Lock four times a second; the rest every few seconds or minutes.
    private func tick() {
        ticks += 1
        checkCapsLock()
        if ticks % 8 == 0 { checkPrivacy() }
        if ticks % 12 == 0 { checkFocus() }
        if ticks % 120 == 0 { checkCalendar() }
        if ticks == 40 || ticks % 2400 == 0 { checkDiskSpace() }
    }

    // MARK: Caps Lock

    private var capsLock: Bool?

    private func checkCapsLock() {
        let now = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
        defer { capsLock = now }
        guard let before = capsLock, before != now, on(Prefs.liveCapsLock) else { return }
        banner(now ? "capslock.fill" : "capslock", now ? .green : .gray, now ? "Caps Lock on" : "Caps Lock off", "",
               seconds: 1.5)
    }

    // MARK: Camera and microphone

    private var cameraOn = false
    private var microphoneOn = false

    private func checkPrivacy() {
        guard on(Prefs.livePrivacy) else {
            cameraOn = false
            microphoneOn = false
            AppState.shared.setPrivacy(.camera, false)
            AppState.shared.setPrivacy(.microphone, false)
            return
        }
        let camera = Self.cameraInUse()
        let microphone = Self.microphoneInUse()
        if camera != cameraOn {
            cameraOn = camera
            AppState.shared.setPrivacy(.camera, camera)
            if camera { banner("video.fill", .green, "Camera in use", "The green dot stays while it is on", seconds: 2.5) }
        }
        if microphone != microphoneOn {
            microphoneOn = microphone
            AppState.shared.setPrivacy(.microphone, microphone)
            // A moment's wait first, for the Live Activity of whatever opened it (a voice assistant listening) to arrive
            // and show it instead.
            if microphone && !camera {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    guard let self, self.microphoneOn, !self.cameraOn, !AppState.shared.microphoneShown else { return }
                    self.banner("mic.fill", .orange, "Microphone in use", "The orange dot stays while it is on",
                                seconds: 2.5)
                }
            }
        }
    }

    /// Whether any app has a camera running, from CoreMediaIO. Asking does not use the camera.
    private static func cameraInUse() -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(0))
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &devices) == noErr else { return false }
        for device in devices {
            var running = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(0))
            var value: UInt32 = 0
            var valueUsed: UInt32 = 0
            let status = CMIOObjectGetPropertyData(device, &running, 0, nil, UInt32(MemoryLayout<UInt32>.size), &valueUsed, &value)
            if status == noErr && value != 0 { return true }
        }
        return false
    }

    /// Whether any app is recording from the default input device.
    private static func microphoneInUse() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return false }
        var running = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &running, 0, nil, &size, &value) == noErr && value != 0
    }

    // MARK: Network

    private let pathMonitor = NWPathMonitor()
    private var lastPath: (online: Bool, kind: String)?

    private func startNetwork() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let kind = path.usesInterfaceType(.wifi) ? "Wi-Fi"
                : path.usesInterfaceType(.wiredEthernet) ? "Ethernet"
                : path.usesInterfaceType(.cellular) ? "your phone" : "the network"
            DispatchQueue.main.async { self?.networkChanged(online: online, kind: kind) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "Isola.network"))
    }

    private func networkChanged(online: Bool, kind: String) {
        defer { lastPath = (online, kind) }
        guard let last = lastPath, on(Prefs.liveNetwork) else { return }
        if last.online && !online {
            banner("wifi.slash", .red, "Offline", "The island will say when you are back")
        } else if !last.online && online {
            banner(kind == "Wi-Fi" ? "wifi" : "network", .green, "Back online", "Connected over \(kind)")
        } else if online && last.kind != kind {
            banner(kind == "Wi-Fi" ? "wifi" : "network", .blue, "Now on \(kind)", "", seconds: 2.5)
        }
    }

    // MARK: Displays

    private var screens: Set<String> = []

    private func startDisplays() {
        screens = Set(NSScreen.screens.map(\.localizedName))
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.displaysChanged() }
    }

    private func displaysChanged() {
        let now = Set(NSScreen.screens.map(\.localizedName))
        defer { screens = now }
        guard on(Prefs.liveDisplays) else { return }
        if let added = now.subtracting(screens).first {
            banner("display", .blue, "Display connected", added)
        } else if let removed = screens.subtracting(now).first {
            banner("display", .gray, "Display disconnected", removed)
        }
    }

    // MARK: Keyboard layout

    private var layout: String?

    private func startKeyboard() {
        layout = Self.currentLayout()
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
            object: nil, queue: .main
        ) { [weak self] _ in self?.keyboardChanged() }
    }

    private static func currentLayout() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    private func keyboardChanged() {
        guard let name = Self.currentLayout(), name != layout else { return }
        layout = name
        guard on(Prefs.liveKeyboard) else { return }
        banner("keyboard", .indigo, name, "Keyboard", seconds: 1.6)
    }

    // MARK: Downloads and screenshots

    private var downloads: FolderWatcher?
    private var screenshots: FolderWatcher?
    private var wantedDownloads = false
    private var wantedScreenshots: URL?

    private func startFolderWatchers() {
        let downloadsOn = on(Prefs.liveDownloads)
        if downloadsOn != wantedDownloads {
            wantedDownloads = downloadsOn
            downloads = downloadsOn
                ? FolderWatcher(url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")) {
                    [weak self] files in self?.downloaded(files)
                }
                : nil
        }
        let folder = on(Prefs.liveScreenshots) ? Self.screenshotFolder() : nil
        if folder != wantedScreenshots {
            wantedScreenshots = folder
            screenshots = folder.flatMap { url in
                FolderWatcher(url: url) { [weak self] files in self?.screenshotSaved(files) }
            }
        }
    }

    /// Where macOS saves screenshots: the Desktop unless changed in the Screenshot app.
    private static func screenshotFolder() -> URL {
        if let path = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"), !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }

    private func downloaded(_ files: [URL]) {
        guard let first = files.first else { return }
        banner("arrow.down.circle.fill", .blue, "Downloaded",
               files.count == 1 ? first.lastPathComponent : "\(files.count) files", seconds: 4,
               action: BannerAction(title: "Show", symbol: "folder") {
                   NSWorkspace.shared.activateFileViewerSelecting(files)
               })
    }

    private func screenshotSaved(_ files: [URL]) {
        let custom = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "name")
        let prefixes = ["Screenshot", "Screen Shot", "Screen Recording"] + (custom.map { [$0] } ?? [])
        let shots = files.filter { url in prefixes.contains { url.lastPathComponent.hasPrefix($0) } }
        guard let first = shots.first else { return }
        let recording = first.lastPathComponent.hasPrefix("Screen Recording") || first.pathExtension.lowercased() == "mov"
        banner(recording ? "record.circle" : "camera.viewfinder", recording ? .red : .gray,
               recording ? "Screen recording saved" : "Screenshot saved", first.lastPathComponent, seconds: 4,
               action: BannerAction(title: "Show", symbol: "folder") {
                   NSWorkspace.shared.activateFileViewerSelecting(shots)
               })
    }

    // MARK: Calendar

    private var announced: Set<String> = []

    /// Five minutes before a meeting, if calendar access was already given for the Calendar tab or widget.
    private func checkCalendar() {
        guard on(Prefs.liveCalendar), EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        let monitor = AppState.shared.calendar
        if monitor.access != .granted { monitor.activate() }
        let now = Date()
        for event in monitor.entries where !event.isAllDay && !announced.contains(event.id) {
            let minutes = event.start.timeIntervalSince(now) / 60
            guard minutes > 0, minutes <= 5 else { continue }
            announced.insert(event.id)
            banner("calendar", event.color, event.title, "Starts in \(max(Int(minutes.rounded()), 1)) min", seconds: 6)
        }
    }

    // MARK: Storage

    private var warnedDisk: Date?

    private func checkDiskSpace() {
        guard on(Prefs.liveDiskSpace),
              let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let free = values.volumeAvailableCapacityForImportantUsage else { return }
        let gigabytes = Double(free) / 1_000_000_000
        guard gigabytes < 10 else { return }
        if let warnedDisk, Date().timeIntervalSince(warnedDisk) < 6 * 3600 { return }
        warnedDisk = Date()
        banner("internaldrive.fill", .orange, "Low on storage", String(format: "%.1f GB left", gigabytes), seconds: 6,
               action: BannerAction(title: "Manage", symbol: "gearshape") {
                   if let url = URL(string: "x-apple.systempreferences:com.apple.settings.Storage") {
                       NSWorkspace.shared.open(url)
                   }
               })
    }

    // MARK: Focus

    private var focusRead = false
    private var focus: String?

    private func checkFocus() {
        guard on(Prefs.liveFocus), let current = Self.currentFocus() else { return }
        let changed = focusRead && current != focus
        focusRead = true
        focus = current
        guard changed else { return }
        if let current {
            banner("moon.fill", .indigo, current, "Focus is on")
        } else {
            banner("moon", .gray, "Focus off", "", seconds: 2.5)
        }
    }

    /// The Focus that is on, nil inside when none is, or nil outside when macOS will not say (Isola needs Full Disk
    /// Access to read the Focus database; there is no public way to ask).
    static func currentFocus() -> String?? {
        let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/DoNotDisturb/DB")
        guard let data = try? Data(contentsOf: base.appendingPathComponent("Assertions.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let records = ((json["data"] as? [[String: Any]])?.first?["storeAssertionRecords"] as? [[String: Any]]) ?? []
        guard let details = records.first?["assertionDetails"] as? [String: Any],
              let mode = details["assertionDetailsModeIdentifier"] as? String else { return .some(nil) }
        var name = "Do Not Disturb"
        if let configData = try? Data(contentsOf: base.appendingPathComponent("ModeConfigurations.json")),
           let config = try? JSONSerialization.jsonObject(with: configData) as? [String: Any],
           let modes = (config["data"] as? [[String: Any]])?.first?["modeConfigurations"] as? [String: Any],
           let entry = modes[mode] as? [String: Any],
           let info = entry["mode"] as? [String: Any],
           let named = info["name"] as? String, !named.isEmpty {
            name = named
        }
        return .some(name)
    }
}

/// Calls back with files that newly appear in a folder, skipping hidden files and downloads still in progress.
final class FolderWatcher {
    let url: URL
    private var source: DispatchSourceFileSystemObject?
    private var known: Set<String> = []
    private let found: ([URL]) -> Void
    private var pending: DispatchWorkItem?

    private static let partial: Set<String> = ["download", "crdownload", "part", "partial", "tmp", "opdownload"]

    init?(url: URL, found: @escaping ([URL]) -> Void) {
        self.url = url
        self.found = found
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        known = Set(listing())
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in self?.changed() }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    deinit {
        source?.cancel()
    }

    private func listing() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).filter { name in
            !name.hasPrefix(".") && !Self.partial.contains((name as NSString).pathExtension.lowercased())
        }
    }

    /// A file often arrives in steps (written, renamed, touched), so wait a moment and look once.
    private func changed() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.scan() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func scan() {
        let now = Set(listing())
        let added = now.subtracting(known)
        known = now
        guard !added.isEmpty else { return }
        found(added.sorted().map { url.appendingPathComponent($0) })
    }
}

/// Alarms and timers from the Clock app, shown as a ringing island with Stop and Snooze. macOS has no way to read
/// another app's notifications, so this uses Accessibility (the permission the media keys already use): it reads the
/// Clock banner when it appears, moves it out of sight, and presses its buttons when you press Isola's.
final class ClockAlerts {
    private var observer: AXObserver?
    private var watchedPID: pid_t = 0
    private var timer: Timer?
    private var pending: DispatchWorkItem?
    private var handled: Set<String> = []

    func start() {
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.attach() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        attach()
    }

    /// Watches the process that draws notification banners, re-attaching if it restarts.
    private func attach() {
        guard UserDefaults.standard.bool(forKey: Prefs.liveClockApp), AXIsProcessTrusted(),
              let center = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first
        else { return }
        let pid = center.processIdentifier
        guard pid != watchedPID else { return }
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            Unmanaged<ClockAlerts>.fromOpaque(refcon).takeUnretainedValue().somethingAppeared()
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else { return }
        let app = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(created, app, kAXWindowCreatedNotification as CFString, refcon)
        AXObserverAddNotification(created, app, kAXCreatedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
        watchedPID = pid
    }

    fileprivate func somethingAppeared() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.scan() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private struct Found {
        var texts: [String] = []
        /// Each button or custom action by its title, with the action to perform on it.
        var actions: [String: (element: AXUIElement, action: String)] = [:]
        var visited = 0
    }

    private func scan() {
        let app = AXUIElementCreateApplication(watchedPID)
        for window in Self.elements(app, kAXWindowsAttribute) {
            var found = Found()
            Self.walk(window, depth: 0, into: &found)
            handle(window: window, found)
        }
    }

    private static func walk(_ element: AXUIElement, depth: Int, into found: inout Found) {
        found.visited += 1
        guard depth < 12, found.visited < 500 else { return }
        let role = string(element, kAXRoleAttribute)
        if role == kAXStaticTextRole, let value = string(element, kAXValueAttribute), !value.isEmpty {
            found.texts.append(value)
        }
        if let description = string(element, kAXDescriptionAttribute), !description.isEmpty {
            found.texts.append(description)
        }
        if role == kAXButtonRole, let title = string(element, kAXTitleAttribute) ?? string(element, kAXDescriptionAttribute) {
            found.actions[title] = (element, kAXPressAction)
        }
        var names: CFArray?
        if AXUIElementCopyActionNames(element, &names) == .success, let names = names as? [String] {
            // Notification banners offer their buttons as custom actions, named like "Name:Stop\nTarget:...".
            for name in names where name.hasPrefix("Name:") {
                let title = name.dropFirst(5).split(separator: "\n").first.map(String.init) ?? ""
                if !title.isEmpty, found.actions[title] == nil { found.actions[title] = (element, name) }
            }
        }
        for child in elements(element, kAXChildrenAttribute) {
            walk(child, depth: depth + 1, into: &found)
        }
    }

    private func handle(window: AXUIElement, _ found: Found) {
        let joined = found.texts.joined(separator: " ")
        let stop = found.actions["Stop"] ?? found.actions["Dismiss"]
        let snooze = found.actions["Snooze"] ?? found.actions["Repeat"]
        let fromClock = joined.contains("Clock")
            || ((joined.contains("Timer") || joined.contains("Alarm")) && (stop != nil || snooze != nil))
        guard fromClock, !handled.contains(joined) else { return }
        handled.insert(joined)
        DispatchQueue.main.asyncAfter(deadline: .now() + 90) { [weak self] in self?.handled.remove(joined) }

        var lines: [String] = []
        for text in found.texts where text != "Clock" && !lines.contains(text) { lines.append(text) }
        let alarm = joined.contains("Alarm")
        Self.hide(window)

        AppState.shared.showBanner(IslandBanner(
            symbol: alarm ? "alarm.fill" : "timer",
            tint: .orange,
            title: lines.first ?? (alarm ? "Alarm" : "Timer"),
            subtitle: lines.dropFirst().first ?? "Clock",
            action: BannerAction(title: "Stop", symbol: "stop.fill") {
                if let stop { _ = AXUIElementPerformAction(stop.element, stop.action as CFString) }
            },
            secondAction: snooze.map { target in
                BannerAction(title: found.actions["Snooze"] != nil ? "Snooze" : "Repeat", symbol: "zzz") {
                    _ = AXUIElementPerformAction(target.element, target.action as CFString)
                }
            },
            ringing: true
        ), for: 60)
    }

    /// Moves the system banner off screen, so only the island shows the alert. Its buttons still work from there.
    private static func hide(_ window: AXUIElement) {
        var far = CGPoint(x: -10_000, y: -10_000)
        if let value = AXValueCreate(.cgPoint, &far) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        }
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return [] }
        return (value as? [AXUIElement]) ?? []
    }
}
