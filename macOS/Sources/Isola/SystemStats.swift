import Foundation
import IOKit.ps

final class SystemStats: ObservableObject {
    /// Each mach_host_self() call adds a reference to the host port that is never given back, so it is taken once.
    private static let host = mach_host_self()

    @Published private(set) var cpu: Double = 0
    @Published private(set) var memory: Double = 0
    @Published private(set) var memoryText = ""
    @Published private(set) var disk: Double = 0
    @Published private(set) var diskText = ""
    @Published private(set) var battery: Int?
    @Published private(set) var isCharging = false
    /// The last minute or so of CPU and memory use, oldest first, for the Home tab's graphs.
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var memoryHistory: [Double] = []
    /// Bytes a second, down and up, across every network interface but loopback.
    @Published private(set) var netDown: Double = 0
    @Published private(set) var netUp: Double = 0
    @Published private(set) var netHistory: [Double] = []

    private var timer: Timer?
    /// How many views are showing the stats. Home and System can overlap while switching tabs, so sampling stops only
    /// when the last one goes.
    private var users = 0
    private var previousTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?
    private var previousNet: [String: (rx: UInt32, tx: UInt32)] = [:]
    private var previousNetAt: Date?

    func start() {
        users += 1
        guard timer == nil else { return }
        sample()
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in self?.sample() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        users = max(users - 1, 0)
        guard users == 0 else { return }
        timer?.invalidate()
        timer = nil
        previousTicks = nil
        previousNetAt = nil
    }

    private func sample() {
        sampleCPU()
        sampleMemory()
        sampleDisk()
        sampleBattery()
        sampleNetwork()
        cpuHistory = Array((cpuHistory + [cpu]).suffix(40))
        memoryHistory = Array((memoryHistory + [memory]).suffix(40))
    }

    private func sampleCPU() {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(Self.host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let now = (user: info.cpu_ticks.0, system: info.cpu_ticks.1, idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
        defer { previousTicks = now }
        guard let before = previousTicks else { return }

        let user = Double(now.user &- before.user)
        let system = Double(now.system &- before.system)
        let idle = Double(now.idle &- before.idle)
        let nice = Double(now.nice &- before.nice)
        let total = user + system + idle + nice
        cpu = total > 0 ? (user + system + nice) / total : 0
    }

    private func sampleMemory() {
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        var stats = vm_statistics64()
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(Self.host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let page = Double(sysconf(_SC_PAGESIZE))
        let used = (Double(stats.active_count) + Double(stats.wire_count) + Double(stats.compressor_page_count)) * page
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        memory = min(used / total, 1)
        memoryText = "\(Self.gigabytes(used)) of \(Self.gigabytes(total))"
    }

    private func sampleDisk() {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let total = values.volumeTotalCapacity,
              let free = values.volumeAvailableCapacityForImportantUsage else { return }
        let used = Double(total) - Double(free)
        disk = total > 0 ? used / Double(total) : 0
        diskText = "\(Self.gigabytes(Double(free))) free"
    }

    private func sampleNetwork() {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return }
        defer { freeifaddrs(list) }
        var counters: [String: (rx: UInt32, tx: UInt32)] = [:]
        var cursor = list
        while let entry = cursor {
            let interface = entry.pointee
            cursor = interface.ifa_next
            guard let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                  let data = interface.ifa_data else { continue }
            let name = String(cString: interface.ifa_name)
            if name.hasPrefix("lo") { continue }
            let stats = data.load(as: if_data.self)
            counters[name] = (stats.ifi_ibytes, stats.ifi_obytes)
        }
        let now = Date()
        if let at = previousNetAt, now.timeIntervalSince(at) > 0 {
            // The counters are 32-bit and wrap, so each interface's difference is taken with wrapping subtraction.
            var rx: UInt64 = 0, tx: UInt64 = 0
            for (name, value) in counters {
                guard let old = previousNet[name] else { continue }
                rx += UInt64(value.rx &- old.rx)
                tx += UInt64(value.tx &- old.tx)
            }
            let seconds = now.timeIntervalSince(at)
            netDown = Double(rx) / seconds
            netUp = Double(tx) / seconds
            netHistory = Array((netHistory + [netDown]).suffix(40))
        }
        previousNet = counters
        previousNetAt = now
    }

    private func sampleBattery() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            battery = nil
            return
        }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let capacity = description[kIOPSCurrentCapacityKey] as? Int else { continue }
            battery = capacity
            isCharging = (description[kIOPSIsChargingKey] as? Bool) ?? false
            return
        }
        battery = nil
    }

    private static func gigabytes(_ bytes: Double) -> String {
        String(format: "%.1f GB", bytes / 1_073_741_824)
    }
}
