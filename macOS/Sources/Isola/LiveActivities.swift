import AppKit
import CoreAudio
import IOBluetooth
import IOKit.ps
import Network
import SwiftUI

/// Watches the Mac for moments worth a glance and shows them in the island: volume and brightness as a bar in the
/// ears, and charging, headphones, drives and VPN as short banners. Each can be switched off in Settings.
final class LiveActivities: NSObject {
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        startVolume()
        startBrightness()
        startPower()
        startDrives()
        startVPN()
        applyPreferences()
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.applyPreferences() }
    }

    private func enabled(_ key: String) -> Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    private func applyPreferences() {
        // Bluetooth is only touched when wanted, because the first use asks for permission.
        if enabled(Prefs.liveHeadphones) {
            startHeadphones()
        } else {
            stopHeadphones()
        }
    }

    private func banner(_ symbol: String, _ tint: Color, _ title: String, _ subtitle: String,
                        seconds: TimeInterval = 4, action: BannerAction? = nil) {
        AppState.shared.showBanner(
            IslandBanner(symbol: symbol, tint: tint, title: title, subtitle: subtitle, action: action), for: seconds)
    }

    // MARK: Volume

    private var outputDevice = AudioObjectID(kAudioObjectUnknown)
    private var watchedVolume: [AudioObjectPropertyAddress] = []
    private var lastVolume: (level: Double, muted: Bool)?

    private lazy var volumeBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.volumeChanged()
    }

    private lazy var outputBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.attachToOutput()
    }

    private func startVolume() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, outputBlock)
        attachToOutput()
    }

    private func attachToOutput() {
        for var address in watchedVolume {
            AudioObjectRemovePropertyListenerBlock(outputDevice, &address, .main, volumeBlock)
        }
        watchedVolume = []

        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return }
        outputDevice = device

        let wanted: [(AudioObjectPropertySelector, AudioObjectPropertyElement)] = [
            (kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyElementMain),
            (kAudioDevicePropertyVolumeScalar, 1),
            (kAudioDevicePropertyVolumeScalar, 2),
            (kAudioDevicePropertyMute, kAudioObjectPropertyElementMain),
        ]
        for (selector, element) in wanted {
            var watched = AudioObjectPropertyAddress(
                mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            guard AudioObjectHasProperty(device, &watched),
                  AudioObjectAddPropertyListenerBlock(device, &watched, .main, volumeBlock) == noErr else { continue }
            watchedVolume.append(watched)
        }
        // A new output device is not a volume change: only remember where it starts.
        lastVolume = readVolume(device)
    }

    private func readVolume(_ device: AudioObjectID) -> (level: Double, muted: Bool)? {
        func scalar(_ element: AudioObjectPropertyElement) -> Double? {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            guard AudioObjectHasProperty(device, &address) else { return nil }
            var value = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
            return Double(value)
        }

        let level: Double
        if let main = scalar(kAudioObjectPropertyElementMain) {
            level = main
        } else {
            let channels = [scalar(1), scalar(2)].compactMap { $0 }
            guard !channels.isEmpty else { return nil }
            level = channels.reduce(0, +) / Double(channels.count)
        }

        var muted = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(device, &address) {
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted)
        }
        return (level, muted != 0)
    }

    private func volumeChanged() {
        guard let now = readVolume(outputDevice) else { return }
        defer { lastVolume = now }
        // Each channel reports its own change; only show real ones.
        if let last = lastVolume, abs(last.level - now.level) < 0.001, last.muted == now.muted { return }
        guard enabled(Prefs.liveVolume) else { return }
        AppState.shared.showHUD(IslandHUD(kind: .volume, level: now.muted ? 0 : now.level, muted: now.muted))
    }

    // MARK: Brightness

    private typealias BrightnessGetter = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private var getBrightness: BrightnessGetter?
    private var lastBrightness: Float?
    private var brightnessTimer: Timer?

    /// macOS has no public brightness API, so this reads it from the private DisplayServices framework, the same
    /// one the brightness keys use. If that ever goes away, brightness simply stops showing.
    private func startBrightness() {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_LAZY),
              let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { return }
        getBrightness = unsafeBitCast(symbol, to: BrightnessGetter.self)

        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.sampleBrightness() }
        RunLoop.main.add(timer, forMode: .common)
        brightnessTimer = timer
    }

    private func builtInDisplay() -> UInt32? {
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                continue
            }
            if CGDisplayIsBuiltin(number.uint32Value) != 0 { return number.uint32Value }
        }
        return nil
    }

    private func sampleBrightness() {
        guard enabled(Prefs.liveBrightness), let getBrightness, let display = builtInDisplay() else {
            lastBrightness = nil
            return
        }
        var value = Float(0)
        guard getBrightness(display, &value) == 0 else { return }
        defer { lastBrightness = value }
        // The keys move brightness in big quick steps; automatic brightness drifts slowly and is left alone.
        guard let last = lastBrightness, abs(value - last) >= 0.04 else { return }
        AppState.shared.showHUD(IslandHUD(kind: .brightness, level: Double(value), muted: false))
    }

    // MARK: Power

    private struct Power: Equatable {
        var percent: Int
        var pluggedIn: Bool
        var charging: Bool
        var full: Bool
    }

    private var lastPower: Power?

    private func startPower() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<LiveActivities>.fromOpaque(context).takeUnretainedValue().powerChanged()
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        lastPower = readPower()
    }

    private func readPower() -> Power? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let capacity = description[kIOPSCurrentCapacityKey] as? Int else { continue }
            let maximum = max(description[kIOPSMaxCapacityKey] as? Int ?? 100, 1)
            let percent = Int((Double(capacity) / Double(maximum) * 100).rounded())
            return Power(
                percent: percent,
                pluggedIn: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                charging: description[kIOPSIsChargingKey] as? Bool ?? false,
                full: description[kIOPSIsChargedKey] as? Bool ?? (percent >= 100)
            )
        }
        return nil
    }

    private func powerChanged() {
        guard let now = readPower() else { return }
        let last = lastPower
        lastPower = now
        guard let last, enabled(Prefs.liveCharging) else { return }

        if now.pluggedIn && !last.pluggedIn {
            banner("battery.100percent.bolt", .green, now.charging ? "Charging" : "Plugged in", "\(now.percent)%")
        } else if !now.pluggedIn && last.pluggedIn {
            banner(Self.batterySymbol(now.percent), now.percent <= 20 ? .orange : .gray, "On battery", "\(now.percent)%")
        } else if now.pluggedIn && now.full && !last.full {
            banner("battery.100percent", .green, "Fully charged", "You can unplug your Mac")
        } else if !now.pluggedIn, let level = [20, 10].first(where: { now.percent <= $0 && last.percent > $0 }) {
            banner(level == 10 ? "battery.0percent" : "battery.25percent", .red, "Low battery",
                   "\(now.percent)% left", seconds: 6)
        }
    }

    private static func batterySymbol(_ percent: Int) -> String {
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    // MARK: Headphones

    private var connectNotification: IOBluetoothUserNotification?
    private var headphonesSince = Date.distantFuture

    private func startHeadphones() {
        guard connectNotification == nil else { return }
        headphonesSince = Date()
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
    }

    private func stopHeadphones() {
        connectNotification?.unregister()
        connectNotification = nil
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        // Already connected devices are reported straight after registering; those are not news.
        guard Date().timeIntervalSince(headphonesSince) > 3, device.deviceClassMajor == 0x04 else { return }
        let name = device.name ?? "Headphones"
        // The battery levels arrive a moment after the connection.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.enabled(Prefs.liveHeadphones) else { return }
            self.banner(Self.headphoneSymbol(name), .blue, name, Self.batteryText(device) ?? "Connected", seconds: 5)
        }
    }

    private static func headphoneSymbol(_ name: String) -> String {
        let lowered = name.lowercased()
        if lowered.contains("airpods pro") { return "airpodspro" }
        if lowered.contains("airpods max") { return "airpodsmax" }
        if lowered.contains("airpods") { return "airpods" }
        return "headphones"
    }

    /// AirPods and Beats report their battery through properties IOBluetooth does not make public. They are read
    /// only if present, so other headphones simply show "Connected".
    private static func batteryText(_ device: IOBluetoothDevice) -> String? {
        func percent(_ key: String) -> Int? {
            guard device.responds(to: NSSelectorFromString(key)),
                  let value = (device.value(forKey: key) as? NSNumber)?.intValue, value > 0 else { return nil }
            return value
        }
        var parts: [String] = []
        if let left = percent("batteryPercentLeft") { parts.append("L \(left)%") }
        if let right = percent("batteryPercentRight") { parts.append("R \(right)%") }
        if parts.isEmpty, let single = percent("batteryPercentSingle") { parts.append("\(single)%") }
        if let box = percent("batteryPercentCase") { parts.append("Case \(box)%") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Drives

    private var announcedDrives: Set<String> = []

    private func startDrives() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] note in
            guard let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            self?.driveMounted(url)
        }
        center.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { [weak self] note in
            guard let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            self?.driveUnmounted(url)
        }
    }

    private func driveMounted(_ url: URL) {
        let keys: Set<URLResourceKey> = [
            .volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsLocalKey, .volumeLocalizedNameKey,
            .volumeAvailableCapacityKey, .volumeTotalCapacityKey,
        ]
        guard enabled(Prefs.liveDrives), let values = try? url.resourceValues(forKeys: keys),
              values.volumeIsLocal ?? false,
              (values.volumeIsEjectable ?? false) || (values.volumeIsRemovable ?? false) else { return }

        let name = values.volumeLocalizedName ?? url.lastPathComponent
        var detail = "Connected"
        if let free = values.volumeAvailableCapacity, let total = values.volumeTotalCapacity, total > 0 {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            detail = "\(formatter.string(fromByteCount: Int64(free))) free of \(formatter.string(fromByteCount: Int64(total)))"
        }
        announcedDrives.insert(url.path)
        banner("externaldrive.fill", .orange, name, detail, seconds: 6,
               action: BannerAction(title: "Eject", symbol: "eject.fill") { [weak self] in self?.eject(url, name) })
    }

    private func eject(_ url: URL, _ name: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: url)
            } catch {
                DispatchQueue.main.async {
                    self?.banner("exclamationmark.triangle.fill", .red, "Could not eject \(name)",
                                 "Something is still using it", seconds: 5)
                }
            }
        }
    }

    private func driveUnmounted(_ url: URL) {
        guard announcedDrives.remove(url.path) != nil, enabled(Prefs.liveDrives) else { return }
        let name = url.lastPathComponent
        banner("eject.fill", .gray, "\(name) ejected", "Safe to disconnect")
    }

    // MARK: VPN

    private let pathMonitor = NWPathMonitor()
    private var vpnActive: Bool?

    private func startVPN() {
        pathMonitor.pathUpdateHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.checkVPN() }
        }
        pathMonitor.start(queue: DispatchQueue(label: "isola.live.path"))
    }

    private func checkVPN() {
        let now = Self.tunnelIsUp()
        let last = vpnActive
        vpnActive = now
        guard let last, last != now, enabled(Prefs.liveVPN) else { return }
        if now {
            banner("lock.shield.fill", .green, "VPN connected", "Your traffic goes through the VPN")
        } else {
            banner("lock.open.fill", .gray, "VPN disconnected", "Back on your normal connection")
        }
    }

    /// VPN apps (WireGuard, Tailscale, IKEv2, most company VPNs) run over a tunnel interface with an IPv4 address.
    /// macOS keeps some tunnel interfaces of its own, but those only carry link-local IPv6.
    private static func tunnelIsUp() -> Bool {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return false }
        defer { freeifaddrs(list) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let interface = current.pointee
            pointer = interface.ifa_next
            let name = String(cString: interface.ifa_name)
            guard ["utun", "ipsec", "ppp"].contains(where: { name.hasPrefix($0) }),
                  let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            if !String(cString: host).hasPrefix("169.254") { return true }
        }
        return false
    }
}

/// Volume or brightness, shown as a bar in the collapsed island's ears.
struct IslandHUD: Equatable {
    enum Kind { case volume, brightness }

    let kind: Kind
    let level: Double
    let muted: Bool

    var symbol: String {
        switch kind {
        case .brightness:
            return level < 0.5 ? "sun.min.fill" : "sun.max.fill"
        case .volume:
            if muted || level <= 0.001 { return "speaker.slash.fill" }
            if level < 0.34 { return "speaker.wave.1.fill" }
            if level < 0.67 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        }
    }
}

struct HUDView: View {
    let hud: IslandHUD
    /// Width hidden behind the camera notch, kept empty. Zero without a notch.
    let notchGap: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: hud.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hud.kind == .brightness ? Color.yellow : Color.white)
                .frame(width: 22)
                .contentTransition(.symbolEffect(.replace))
            if notchGap > 0 { Spacer(minLength: notchGap) }
            bar
                .frame(width: notchGap > 0 ? 54 : nil)
            Text("\(Int((hud.level * 100).rounded()))")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .frame(width: 24, alignment: .trailing)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .animation(.easeOut(duration: 0.12), value: hud)
    }

    private var bar: some View {
        Capsule()
            .fill(Color.white.opacity(0.2))
            .frame(height: 5)
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    Capsule()
                        .fill(hud.kind == .brightness ? Color.yellow : Color.white)
                        .frame(width: geometry.size.width * min(max(hud.level, 0), 1))
                }
            }
    }
}
