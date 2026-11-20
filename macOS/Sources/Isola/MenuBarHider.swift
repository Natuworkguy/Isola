import AppKit

/// Tidies the menu bar: icons you ⌘-drag to the left of Isola's divider hide, and the chevron beside it shows them
/// again (they hide once more after 15 seconds). Turned on in Settings, under Tools.
final class MenuBarHider {
    static let shared = MenuBarHider()

    private var chevron: NSStatusItem?
    private var divider: NSStatusItem?
    private var hidden = false
    private var rehide: DispatchWorkItem?
    private static let dividerWidth: CGFloat = 14

    func start() {
        apply()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil,
                                               queue: .main) { [weak self] _ in self?.apply() }
    }

    private func apply() {
        let on = UserDefaults.standard.bool(forKey: Prefs.toolMenuBar)
        if on, chevron == nil {
            // The chevron first, then the divider: a newer item goes to the left of the older ones.
            let chevron = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            chevron.autosaveName = "isola.hider.chevron"
            chevron.button?.target = self
            chevron.button?.action = #selector(toggle)
            chevron.button?.toolTip = "Show or hide the menu bar icons left of the divider"
            self.chevron = chevron
            let divider = NSStatusBar.system.statusItem(withLength: Self.dividerWidth)
            divider.autosaveName = "isola.hider.divider"
            divider.button?.image = NSImage(systemSymbolName: "line.diagonal", accessibilityDescription: "Divider")
            divider.button?.appearsDisabled = true
            divider.button?.toolTip = "⌘-drag icons to the left of this to hide them"
            self.divider = divider
            setHidden(true)
        } else if !on, let chevron {
            NSStatusBar.system.removeStatusItem(chevron)
            if let divider { NSStatusBar.system.removeStatusItem(divider) }
            self.chevron = nil
            divider = nil
            hidden = false
        }
    }

    @objc private func toggle() {
        setHidden(!hidden)
    }

    private func setHidden(_ hide: Bool) {
        hidden = hide
        // Hiding is the divider growing so wide it pushes everything left of it off the screen.
        divider?.length = hide ? 10_000 : Self.dividerWidth
        chevron?.button?.image = NSImage(systemSymbolName: hide ? "chevron.left" : "chevron.right",
                                         accessibilityDescription: hide ? "Show icons" : "Hide icons")
        rehide?.cancel()
        if !hide {
            let work = DispatchWorkItem { [weak self] in self?.setHidden(true) }
            rehide = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
        }
    }
}
