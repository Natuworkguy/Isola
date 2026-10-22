import AppKit
import SwiftUI

extension Notification.Name {
    static let isolaOpenSettings = Notification.Name("IsolaOpenSettings")
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSWindowDelegate {
    private var notch: NotchController?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private let hotKey = HotKey()

    func applicationDidFinishLaunching(_ notification: Notification) {
        replaceOtherCopies()
        Prefs.registerDefaults()

        let state = AppState.shared
        state.clipboard.start()
        state.nowPlaying.start()
        state.live.start()
        state.systemActivities.start()
        state.mediaKeys.start()
        MemoryGuard.shared.start()

        notch = NotchController(state: state)
        notch?.show()
        buildStatusItem()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.72)) { state.arrived = true }
        }

        NotificationCenter.default.addObserver(
            forName: .isolaOpenSettings, object: nil, queue: .main
        ) { [weak self] _ in self?.openSettings() }

        hotKey.pressed = { [weak self] in self?.notch?.toggleFromKeyboard() }
        hotKey.setEnabled(UserDefaults.standard.bool(forKey: Prefs.hotKey))
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.hotKey.setEnabled(UserDefaults.standard.bool(forKey: Prefs.hotKey)) }
        FloatingPlayer.shared.restore()
    }

    /// Only one Isola runs at a time: a newly launched copy quits any that is already running (a second build, or one
    /// started with `open -n`) and takes over. Links still go to the running copy, through LaunchServices.
    private func replaceOtherCopies() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let me = NSRunningApplication.current.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != me }
        guard !others.isEmpty else { return }
        others.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(3)
        while others.contains(where: { !$0.isTerminated }), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        others.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
    }

    /// isola://notify and isola://activity links from other apps and scripts, and files opened with Isola
    /// (`open -a Isola report.pdf`, or dropped on its icon), which go to the File Tray.
    func application(_ application: NSApplication, open urls: [URL]) {
        let files = urls.filter(\.isFileURL)
        if !files.isEmpty {
            let state = AppState.shared
            state.tray.add(files)
            state.showBanner(IslandBanner(
                symbol: "tray.and.arrow.down.fill", tint: .blue, title: "Added to the tray",
                subtitle: files.count == 1 ? files[0].lastPathComponent : "\(files.count) files"), for: 3)
        }
        for url in urls where !url.isFileURL {
            if url.host?.lowercased() == "activity" {
                ActivityLink.handle(url)
            } else {
                NotifyLink.handle(url)
            }
        }
    }

    /// Opening Isola again while it runs, from Applications, Launchpad or Spotlight, opens Settings. Without it nothing
    /// would happen: Isola has no window of its own to bring forward.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.clipboard.stop()
        AppState.shared.nowPlaying.stop()
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // The logo's i as a template image, so macOS tints it for light and dark menu bars.
        if let logo = NSImage(named: "MenuIcon") {
            logo.isTemplate = true
            logo.accessibilityDescription = "Isola"
            item.button?.image = logo
        } else {
            item.button?.image = NSImage(systemSymbolName: "circle.hexagongrid.fill", accessibilityDescription: "Isola")
        }

        let menu = NSMenu()
        add(menu, "Toggle Island", #selector(toggleIsland), "")
        add(menu, "Pin Island Open", #selector(togglePin), "")
        add(menu, "Floating Player", #selector(toggleFloatingPlayer), "")
        menu.addItem(.separator())
        add(menu, "Clear Clipboard History", #selector(clearClipboard), "")
        add(menu, "Clear File Tray", #selector(clearTray), "")
        menu.addItem(.separator())
        add(menu, "Settings…", #selector(openSettings), ",")
        add(menu, "About Isola", #selector(showAbout), "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Isola", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String) {
        let entry = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        entry.target = self
    }

    @objc private func toggleIsland() { withAnimation { AppState.shared.isExpanded.toggle() } }

    @objc private func togglePin() {
        let state = AppState.shared
        state.isPinned.toggle()
        if state.isPinned { withAnimation { state.isExpanded = true } }
    }

    @objc private func toggleFloatingPlayer() { FloatingPlayer.shared.toggle() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(togglePin): menuItem.state = AppState.shared.isPinned ? .on : .off
        case #selector(toggleFloatingPlayer): menuItem.state = FloatingPlayer.shared.isShown ? .on : .off
        default: break
        }
        return true
    }

    @objc private func clearClipboard() { AppState.shared.clipboard.clear() }
    @objc private func clearTray() { AppState.shared.tray.clear() }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Isola",
            .credits: NSAttributedString(string: "Made by Natuworkguy"),
        ])
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Isola Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView())
            window.center()
            window.delegate = self
            settingsWindow = window
        }
        // An ordinary app, with a Dock icon, while Settings is open. Screen Time only sees apps that come to the front:
        // this is where it asks for more time when Isola is limited, and what lists Isola so it can be Always Allowed.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === settingsWindow else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}
