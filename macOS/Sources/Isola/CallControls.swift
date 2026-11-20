import AppKit
import CoreAudio
import SwiftUI

/// Calls in Zoom, Teams and FaceTime: while one is on (its app open and the microphone in use) the island counts the
/// call's time, and a banner as it starts offers Mute and Leave. Mute is the Mac's own (the microphone itself), so it
/// works whatever the app; ⌃⌥⇧M toggles it any time.
final class CallControls {
    static let shared = CallControls()
    private static let activityID = "isola.call"

    /// The apps it knows how to leave a call in, and the keys each uses for it.
    private struct CallApp {
        let bundle: String
        let name: String
        let leave: (key: CGKeyCode, flags: CGEventFlags)?
    }

    private let apps: [CallApp] = [
        CallApp(bundle: "us.zoom.xos", name: "Zoom", leave: (13, .maskCommand)),                       // ⌘W
        CallApp(bundle: "com.microsoft.teams2", name: "Teams", leave: (4, [.maskCommand, .maskShift])),  // ⌘⇧H
        CallApp(bundle: "com.microsoft.teams", name: "Teams", leave: (4, [.maskCommand, .maskShift])),
        CallApp(bundle: "com.apple.FaceTime", name: "FaceTime", leave: (13, .maskCommand)),
        CallApp(bundle: "com.cisco.webexmeetingsapp", name: "Webex", leave: nil),
    ]

    private var timer: Timer?
    private var current: (app: CallApp, pid: pid_t, since: Date)?
    private var savedVolume: Float32?

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.check() }
    }

    private func check() {
        guard UserDefaults.standard.bool(forKey: Prefs.liveCalls) else {
            if current != nil { ended() }
            return
        }
        let running = NSWorkspace.shared.runningApplications
        let found = apps.lazy.compactMap { app -> (CallApp, pid_t)? in
            guard let process = running.first(where: { $0.bundleIdentifier == app.bundle }) else { return nil }
            return (app, process.processIdentifier)
        }.first
        let onCall = found != nil && Self.microphoneInUse()
        if onCall, current == nil, let found {
            let (app, pid) = found
            current = (app, pid, Date())
            update()
            var banner = IslandBanner(symbol: "phone.fill", tint: .green, title: "On a call",
                                      subtitle: "\(app.name) · ⌃⌥⇧M mutes")
            banner.action = BannerAction(title: "Mute", symbol: "mic.slash.fill") { [weak self] in self?.toggleMute() }
            if app.leave != nil {
                banner.secondAction = BannerAction(title: "Leave", symbol: "phone.down.fill") { [weak self] in self?.leave() }
            }
            AppState.shared.showBanner(banner, for: 6)
        } else if !onCall, current != nil {
            ended()
        }
    }

    private func update() {
        guard let current else { return }
        let muted = Self.inputMuted()
        var activity = LiveActivity(id: Self.activityID, symbol: muted ? "mic.slash.fill" : "phone.fill",
                                    tint: muted ? .red : .green, title: muted ? "Muted" : "On a call")
        activity.subtitle = current.app.name
        activity.since = current.since
        activity.priority = 3
        activity.mic = muted ? .off : .on
        AppState.shared.setActivity(activity)
    }

    private func ended() {
        if Self.inputMuted() { _ = Self.setInputMuted(false) }  // the microphone isn't left off after the call
        current = nil
        AppState.shared.endActivity(Self.activityID)
    }

    func toggleMute() {
        let mute = !Self.inputMuted()
        guard Self.setInputMuted(mute) else {
            AppState.shared.showBanner(IslandBanner(symbol: "mic.fill", tint: .orange, title: "Couldn't mute",
                                                    subtitle: "This microphone can't be muted by the Mac"), for: 3)
            return
        }
        AppState.shared.showBanner(IslandBanner(symbol: mute ? "mic.slash.fill" : "mic.fill", tint: mute ? .red : .green,
                                                title: mute ? "Muted" : "Unmuted", subtitle: ""), for: 1.5)
        update()
    }

    private func leave() {
        guard let current, let keys = current.app.leave else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keys.key, keyDown: down)
            event?.flags = keys.flags
            event?.postToPid(current.pid)
        }
    }

    // MARK: The default microphone

    private static func defaultInput() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        return device
    }

    static func microphoneInUse() -> Bool {
        guard let device = defaultInput() else { return false }
        var running = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &running, 0, nil, &size, &value) == noErr && value != 0
    }

    private static var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeInput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    static func inputMuted() -> Bool {
        guard let device = defaultInput() else { return false }
        var address = muteAddress
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr { return value != 0 }
        return shared.savedVolume != nil
    }

    /// Mutes the microphone: with its own mute where it has one, else by turning its volume to nothing and back.
    static func setInputMuted(_ mute: Bool) -> Bool {
        guard let device = defaultInput() else { return false }
        var address = muteAddress
        var settable = DarwinBoolean(false)
        if AudioObjectHasProperty(device, &address),
           AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue {
            var value: UInt32 = mute ? 1 : 0
            return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
        }
        var volume = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                                mScope: kAudioDevicePropertyScopeInput,
                                                mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &volume) else { return false }
        var level: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        if mute {
            _ = AudioObjectGetPropertyData(device, &volume, 0, nil, &size, &level)
            shared.savedVolume = level
            level = 0
        } else {
            level = shared.savedVolume ?? 0.75
            shared.savedVolume = nil
        }
        return AudioObjectSetPropertyData(device, &volume, 0, nil, size, &level) == noErr
    }
}
