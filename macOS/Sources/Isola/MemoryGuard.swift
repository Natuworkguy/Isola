import AppKit

extension Notification.Name {
    /// Isola is over its memory limit: whatever keeps a cache lets it go.
    static let isolaTrimMemory = Notification.Name("IsolaTrimMemory")
}

/// A ceiling on the memory Isola may use, so nothing going wrong inside it can slow the whole Mac down. Every 30
/// seconds it reads its own footprint, the figure Activity Monitor shows. Over the limit, the caches go first; still
/// over a minute later, Isola starts a fresh copy of itself, which takes over from this one.
final class MemoryGuard {
    static let shared = MemoryGuard()

    private var timer: Timer?
    private var trimmedAt: Date?

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.check() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Isola's memory footprint, in bytes.
    static func footprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : nil
    }

    private func check() {
        let megabytes = UserDefaults.standard.integer(forKey: Prefs.memoryLimit)
        guard megabytes > 0, let used = Self.footprint() else { return }
        guard used > UInt64(megabytes) * 1_048_576 else {
            trimmedAt = nil
            return
        }
        if let trimmedAt {
            if Date().timeIntervalSince(trimmedAt) >= 60 { restart() }
        } else {
            trimmedAt = Date()
            NotificationCenter.default.post(name: .isolaTrimMemory, object: nil)
        }
    }

    /// A fresh copy of Isola, which quits this one as it starts (AppDelegate.replaceOtherCopies).
    private func restart() {
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-n", Bundle.main.bundlePath]
        do {
            try open.run()
            timer?.invalidate()
            timer = nil
        } catch {
            trimmedAt = nil
        }
    }
}
