import AppKit

/// Isola lives in the menu bar and the notch, so it has no Dock icon. Its ordinary windows (Settings, the welcome
/// tour) are different: while one is open Isola becomes an ordinary app, with its icon in the Dock, its windows in
/// the Dock's menu and Mission Control, Command-Tab to it, and a menu bar of its own. When the last one closes it
/// goes back to the menu bar.
enum DockPresence {
    private static var windows: [NSWindow] = []
    private static var observers: [NSObjectProtocol] = []

    /// Shows WINDOW in front, with Isola in the Dock for as long as it stays open.
    static func show(_ window: NSWindow) {
        if !windows.contains(where: { $0 === window }) {
            windows.append(window)
            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { note in closed(note.object as? NSWindow) })
        }
        window.collectionBehavior.insert(.managed)
        window.collectionBehavior.remove(.transient)
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
            // Set by the bundle, but a menu bar app that turns into an ordinary one shows a blank icon without it.
            if let icon = NSImage(named: "AppIcon") { NSApp.applicationIconImage = icon }
            installMenu()
        }
        bringForward(window)
        // A newly regular app is only let to the front once the Dock knows about it: ask again a moment later.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { bringForward(window) }
    }

    private static func bringForward(_ window: NSWindow) {
        guard window.isVisible || windows.contains(where: { $0 === window }) else { return }
        NSApp.unhide(nil)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private static func closed(_ window: NSWindow?) {
        guard let window, let at = windows.firstIndex(where: { $0 === window }) else { return }
        windows.remove(at: at)
        NotificationCenter.default.removeObserver(observers.remove(at: at))
        guard windows.isEmpty else { return }
        // After the window has gone, so it doesn't flash as the Dock icon leaves.
        DispatchQueue.main.async {
            guard windows.isEmpty else { return }
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// The menu bar Isola has while it is in the Dock: its own menu, Edit (so copy and paste work in text fields)
    /// and Window.
    private static func installMenu() {
        guard NSApp.mainMenu == nil || NSApp.mainMenu?.items.isEmpty == true else { return }
        let main = NSMenu()

        let app = NSMenu(title: "Isola")
        app.addItem(withTitle: "About Isola", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        let settings = app.addItem(withTitle: "Settings…", action: #selector(MenuTarget.openSettings), keyEquivalent: ",")
        settings.target = MenuTarget.shared
        app.addItem(.separator())
        app.addItem(withTitle: "Hide Isola", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = app.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        app.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit Isola", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(withTitle: "Isola", action: nil, keyEquivalent: "").submenu = app

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(withTitle: "Window", action: nil, keyEquivalent: "").submenu = window
        NSApp.windowsMenu = window

        NSApp.mainMenu = main
    }

    private final class MenuTarget: NSObject {
        static let shared = MenuTarget()
        @objc func openSettings() { NotificationCenter.default.post(name: .isolaOpenSettings, object: nil) }
    }
}
