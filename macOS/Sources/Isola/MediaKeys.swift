import AppKit
import ApplicationServices
import CoreAudio

/// Takes over the volume, mute and brightness keys so the macOS overlay never appears and only Isola's bar shows.
/// Only keys whose indicator is switched on in Settings are taken; every other key, and any key Isola cannot
/// handle (an output with no volume control, a Mac with no built-in display), goes to macOS as usual.
///
/// Listening to keys needs the Accessibility permission.
final class MediaKeys: ObservableObject {
    @Published private(set) var needsPermission = false

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var permissionTimer: Timer?
    private var asked = false

    private typealias BrightnessGetter = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias BrightnessSetter = @convention(c) (UInt32, Float) -> Int32
    private var getBrightness: BrightnessGetter?
    private var setBrightness: BrightnessSetter?

    // NX_KEYTYPE values carried by system-defined key events.
    private enum Key: Int {
        case soundUp = 0, soundDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7
    }

    init() {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        if let handle = dlopen(path, RTLD_LAZY) {
            getBrightness = dlsym(handle, "DisplayServicesGetBrightness").map { unsafeBitCast($0, to: BrightnessGetter.self) }
            setBrightness = dlsym(handle, "DisplayServicesSetBrightness").map { unsafeBitCast($0, to: BrightnessSetter.self) }
        }
    }

    func start() {
        applyPreferences()
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.applyPreferences() }
    }

    private var defaults: UserDefaults { .standard }
    private var volumeWanted: Bool { defaults.bool(forKey: Prefs.hideSystemHUD) && defaults.bool(forKey: Prefs.liveVolume) }
    private var brightnessWanted: Bool {
        defaults.bool(forKey: Prefs.hideSystemHUD) && defaults.bool(forKey: Prefs.liveBrightness)
    }

    private func applyPreferences() {
        if volumeWanted || brightnessWanted {
            install()
        } else {
            uninstall()
        }
    }

    // MARK: The event tap

    private func install() {
        guard tap == nil else { return }
        guard AXIsProcessTrusted() else {
            waitForPermission()
            return
        }
        permissionTimer?.invalidate()
        permissionTimer = nil

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << 14), // NX_SYSDEFINED: media and brightness keys
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                return Unmanaged<MediaKeys>.fromOpaque(context).takeUnretainedValue().handle(type, event)
            },
            userInfo: context
        ) else {
            waitForPermission()
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        needsPermission = false
    }

    private func uninstall() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        needsPermission = false
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    /// Asks once, then checks every two seconds so the keys start working as soon as permission is granted.
    private func waitForPermission() {
        needsPermission = true
        if !asked {
            asked = true
            let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        }
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard AXIsProcessTrusted() else { return }
            self?.permissionTimer?.invalidate()
            self?.permissionTimer = nil
            self?.applyPreferences()
        }
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        guard type.rawValue == 14, let keyEvent = NSEvent(cgEvent: event), keyEvent.subtype.rawValue == 8 else {
            return pass
        }
        let data = keyEvent.data1
        guard let key = Key(rawValue: (data & 0xFFFF0000) >> 16) else { return pass }
        let pressed = ((data & 0x0000FFFF) & 0xFF00) >> 8 == 0x0A
        // Option-Shift moves in quarter steps, as macOS does.
        let step = keyEvent.modifierFlags.contains([.option, .shift]) ? 1.0 / 64 : 1.0 / 16

        switch key {
        case .soundUp, .soundDown, .mute:
            guard volumeWanted, let device = defaultOutput(), canSetVolume(device) else { return pass }
            if pressed { changeVolume(key, step: step, on: device) }
            return nil
        case .brightnessUp, .brightnessDown:
            guard brightnessWanted, let display = builtInDisplay(), getBrightness != nil, setBrightness != nil else {
                return pass
            }
            if pressed { changeBrightness(up: key == .brightnessUp, step: step, display: display) }
            return nil
        }
    }

    // MARK: Volume

    private func address(_ selector: AudioObjectPropertySelector,
                         _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
                         scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    private func defaultOutput() -> AudioObjectID? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var where_ = address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &where_, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        return device
    }

    private func settable(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector,
                          _ element: AudioObjectPropertyElement) -> Bool {
        var where_ = address(selector, element)
        guard AudioObjectHasProperty(device, &where_) else { return false }
        var result = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(device, &where_, &result) == noErr && result.boolValue
    }

    /// The elements that carry the volume: the main one, or the left and right channels on devices without it.
    private func volumeElements(_ device: AudioObjectID) -> [AudioObjectPropertyElement] {
        if settable(device, kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyElementMain) {
            return [kAudioObjectPropertyElementMain]
        }
        return [1, 2].filter { settable(device, kAudioDevicePropertyVolumeScalar, $0) }
    }

    private func canSetVolume(_ device: AudioObjectID) -> Bool {
        !volumeElements(device).isEmpty
    }

    private func readVolume(_ device: AudioObjectID, _ elements: [AudioObjectPropertyElement]) -> Double {
        let values: [Double] = elements.compactMap { element in
            var where_ = address(kAudioDevicePropertyVolumeScalar, element)
            var value = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectGetPropertyData(device, &where_, 0, nil, &size, &value) == noErr else { return nil }
            return Double(value)
        }
        return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    private func isMuted(_ device: AudioObjectID) -> Bool {
        var where_ = address(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(device, &where_) else { return false }
        var muted = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(device, &where_, 0, nil, &size, &muted)
        return muted != 0
    }

    private func setMuted(_ muted: Bool, _ device: AudioObjectID) {
        guard settable(device, kAudioDevicePropertyMute, kAudioObjectPropertyElementMain) else { return }
        var where_ = address(kAudioDevicePropertyMute)
        var value = UInt32(muted ? 1 : 0)
        AudioObjectSetPropertyData(device, &where_, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    /// Changing the volume or mute fires Isola's own volume listener, which shows the bar.
    private func changeVolume(_ key: Key, step: Double, on device: AudioObjectID) {
        if key == .mute {
            setMuted(!isMuted(device), device)
            return
        }
        let elements = volumeElements(device)
        let current = readVolume(device, elements)
        // Land on the step grid, like macOS, so repeated presses reach exactly 0 and 100.
        let steps = (current / step).rounded()
        let target = min(max((key == .soundUp ? steps + 1 : steps - 1) * step, 0), 1)
        if key == .soundUp { setMuted(false, device) }
        for element in elements {
            var where_ = address(kAudioDevicePropertyVolumeScalar, element)
            var value = Float32(target)
            AudioObjectSetPropertyData(device, &where_, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        }
    }

    // MARK: Brightness

    private func builtInDisplay() -> UInt32? {
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                continue
            }
            if CGDisplayIsBuiltin(number.uint32Value) != 0 { return number.uint32Value }
        }
        return nil
    }

    private func changeBrightness(up: Bool, step: Double, display: UInt32) {
        guard let getBrightness, let setBrightness else { return }
        var current = Float(0)
        guard getBrightness(display, &current) == 0 else { return }
        let steps = (Double(current) / step).rounded()
        let target = min(max((up ? steps + 1 : steps - 1) * step, 0), 1)
        _ = setBrightness(display, Float(target))
        AppState.shared.showHUD(IslandHUD(kind: .brightness, level: target, muted: false))
    }
}
