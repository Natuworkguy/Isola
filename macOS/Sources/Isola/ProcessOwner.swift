import AppKit

/// The app a process plays sound for. Web pages, in Safari or in any app's web view, play through WebKit's own
/// processes, and macOS and CoreAudio report those under their own names (com.apple.WebKit.GPU) rather than the app's.
enum ProcessOwner {
    private typealias Responsible = @convention(c) (pid_t) -> pid_t

    /// The process macOS holds responsible for another: for a helper, the app that started it. Not in the SDK's
    /// headers, so looked up at run time; without it, WebKit's processes count as Safari's (see webKitHost).
    private static let responsible: Responsible? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid")
        else { return nil }
        return unsafeBitCast(symbol, to: Responsible.self)
    }()

    /// The bundle ID of the app that the process with BUNDLE and PID plays for: its own when it is an app, or for a
    /// helper the app it works for. Nil when that can't be told.
    static func appBundleID(bundleID bundle: String, pid: pid_t?) -> String? {
        if let pid, pid > 0, let process = NSRunningApplication(processIdentifier: pid) {
            if isApp(process) { return process.bundleIdentifier ?? (bundle.isEmpty ? nil : bundle) }
            if let owner = responsibleApp(for: pid) { return owner }
        }
        return bundle.hasPrefix("com.apple.WebKit") ? webKitHost() : nil
    }

    private static func responsibleApp(for pid: pid_t) -> String? {
        guard let responsible else { return nil }
        let owner = responsible(pid)
        guard owner > 0, owner != pid, let app = NSRunningApplication(processIdentifier: owner), isApp(app) else {
            return nil
        }
        return app.bundleIdentifier
    }

    /// True for an app of its own: an .app bundle that isn't a helper inside another app.
    private static func isApp(_ process: NSRunningApplication) -> Bool {
        guard let url = process.bundleURL, url.pathExtension.lowercased() == "app" else { return false }
        return !(url.deletingLastPathComponent().path.lowercased() + "/").contains(".app/")
    }

    /// Whose page a WebKit process plays when macOS can't say: Safari, or Safari Technology Preview if only it is
    /// open, or else a Safari web app, the one in front first.
    private static func webKitHost() -> String? {
        let ids = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
            .compactMap(\.bundleIdentifier)
        if ids.contains("com.apple.Safari") { return "com.apple.Safari" }
        if ids.contains("com.apple.SafariTechnologyPreview") { return "com.apple.SafariTechnologyPreview" }
        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier, front.hasPrefix("com.apple.Safari.WebApp") {
            return front
        }
        return ids.first { $0.hasPrefix("com.apple.Safari.WebApp") }
    }
}
