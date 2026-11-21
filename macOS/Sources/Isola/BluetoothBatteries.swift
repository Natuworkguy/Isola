import Foundation
import IOKit
import SwiftUI

/// One Bluetooth device and how charged it is: a keyboard, mouse or trackpad, headphones, a game controller, a pen.
struct BluetoothDevice: Identifiable, Equatable {
    var id: String { name }
    let name: String
    /// What it is, as a symbol.
    let symbol: String
    /// The main level, or the lowest of left and right for earbuds (0 to 100).
    let level: Int
    /// Each part, for earbuds: "L 80%", "R 75%", "Case 40%".
    let parts: [String]

    var summary: String { parts.isEmpty ? "\(level)%" : parts.joined(separator: " · ") }
    var low: Bool { level <= 15 }
}

/// The battery of every Bluetooth device connected to the Mac, not only AirPods. Two sources, merged by name:
/// the HID devices in the I/O registry (Apple's keyboards, mice and trackpads, and many others, which report a
/// BatteryPercent), and what System Information knows (headphones, controllers and everything else that sends its
/// level over Bluetooth). Looked at every couple of minutes, on a background queue, and when a device connects.
final class BluetoothBatteries: ObservableObject {
    static let shared = BluetoothBatteries()

    @Published private(set) var devices: [BluetoothDevice] = []
    /// Called on the main queue the first time a device drops to 15% or below (and again after it is charged).
    var onLow: ((BluetoothDevice) -> Void)?

    private let queue = DispatchQueue(label: "isola.bluetooth-batteries", qos: .utility)
    private var timer: Timer?
    private var warned: Set<String> = []
    private var running = false

    func start() {
        guard timer == nil else { return }
        refresh()
        let timer = Timer(timeInterval: 120, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Looks again now, and calls DONE on the main queue with the result.
    func refresh(_ done: (([BluetoothDevice]) -> Void)? = nil) {
        guard !running else { return }
        running = true
        queue.async { [weak self] in
            var found: [String: BluetoothDevice] = [:]
            for device in Self.profiled() { found[device.name] = device }
            // The registry's reading is the fresher one for the devices it knows.
            for device in Self.registry() { found[device.name] = device }
            let list = found.values.sorted { $0.level < $1.level }
            DispatchQueue.main.async {
                guard let self else { return }
                self.running = false
                if list != self.devices { withAnimation(.smooth(duration: 0.3)) { self.devices = list } }
                for device in list {
                    if device.low, !self.warned.contains(device.name) {
                        self.warned.insert(device.name)
                        self.onLow?(device)
                    } else if device.level >= 30 {
                        self.warned.remove(device.name)
                    }
                }
                done?(list)
            }
        }
    }

    func device(named name: String) -> BluetoothDevice? { devices.first { $0.name == name } }

    // MARK: Sources

    /// HID devices with a BatteryPercent in the I/O registry.
    private static func registry() -> [BluetoothDevice] {
        var found: [BluetoothDevice] = []
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"),
                                           &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            func value(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }
            guard let percent = (value("BatteryPercent") as? NSNumber)?.intValue, percent > 0,
                  let name = value("Product") as? String, !name.isEmpty else { continue }
            found.append(BluetoothDevice(name: name, symbol: symbol(for: name, kind: ""), level: min(percent, 100), parts: []))
        }
        return found
    }

    /// What System Information lists as connected, with a battery level.
    private static func profiled() -> [BluetoothDevice] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json", "-detailLevel", "basic"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }
        var found: [BluetoothDevice] = []
        for section in sections {
            // Connected devices are a list of one-key dictionaries: the device's name, and what is known about it.
            for entry in section["device_connected"] as? [[String: Any]] ?? [] {
                for (name, info) in entry {
                    guard let info = info as? [String: Any] else { continue }
                    func level(_ key: String) -> Int? {
                        guard let text = info[key] as? String else { return nil }
                        return Int(text.filter(\.isNumber)).flatMap { $0 > 0 ? min($0, 100) : nil }
                    }
                    let main = level("device_batteryLevelMain") ?? level("device_batteryLevel")
                    let left = level("device_batteryLevelLeft"), right = level("device_batteryLevelRight")
                    let box = level("device_batteryLevelCase")
                    var parts: [String] = []
                    if let left { parts.append("L \(left)%") }
                    if let right { parts.append("R \(right)%") }
                    if let box { parts.append("Case \(box)%") }
                    guard let lowest = [main, left, right].compactMap({ $0 }).min() else { continue }
                    let kind = (info["device_minorType"] as? String ?? "").lowercased()
                    found.append(BluetoothDevice(name: name, symbol: symbol(for: name, kind: kind), level: lowest,
                                                 parts: left != nil || right != nil ? parts : (box != nil ? ["\(lowest)%"] + parts : [])))
                }
            }
        }
        return found
    }

    /// A symbol for a device, from its name and the kind System Information gives it.
    static func symbol(for name: String, kind: String) -> String {
        let n = name.lowercased()
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods") { return "airpods" }
        if n.contains("trackpad") { return "rectangle.and.hand.point.up.left.fill" }
        if n.contains("mouse") || kind.contains("mouse") { return "magicmouse.fill" }
        if n.contains("keyboard") || kind.contains("keyboard") { return "keyboard.fill" }
        if n.contains("controller") || n.contains("dualsense") || n.contains("xbox") || kind.contains("gamepad") {
            return "gamecontroller.fill"
        }
        if n.contains("pencil") || n.contains("pen") { return "applepencil" }
        if n.contains("watch") { return "applewatch" }
        if n.contains("speaker") || kind.contains("speaker") { return "hifispeaker.fill" }
        if kind.contains("headphone") || kind.contains("headset") || n.contains("buds") || n.contains("beats") { return "headphones" }
        return "dot.radiowaves.left.and.right"
    }
}
