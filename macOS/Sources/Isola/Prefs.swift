import Foundation

enum Prefs {
    static let openWith = "openWith"
    static let hoverDelay = "hoverDelay"
    static let hoverArea = "hoverArea"
    static let expandOnFileDrag = "expandOnFileDrag"
    static let haptics = "haptics"
    static let display = "display"
    static let style = "style"
    static let material = "material"
    static let idleBehavior = "idleBehavior"
    static let idleWidth = "idleWidth"
    static let idleHeight = "idleHeight"
    static let floatingGap = "topGap"
    static let menuOverhang = "menuOverhang"
    static let artTint = "artTint"
    static let clipboardLimit = "clipboardLimit"
    static let memoryLimit = "memoryLimit"
    static let notifyLinks = "notifyLinks"
    static let liveVolume = "live.volume"
    static let liveBrightness = "live.brightness"
    static let hideSystemHUD = "live.hideSystemHUD"
    static let liveCharging = "live.charging"
    static let liveHeadphones = "live.headphones"
    static let liveDrives = "live.drives"
    static let liveVPN = "live.vpn"
    static let shakeBasket = "shakeBasket"
    static let liveTimers = "live.timers"
    static let liveClockApp = "live.clockApp"
    static let livePrivacy = "live.privacy"
    static let liveDownloads = "live.downloads"
    static let liveScreenshots = "live.screenshots"
    static let liveNetwork = "live.network"
    static let liveDisplays = "live.displays"
    static let liveCapsLock = "live.capsLock"
    static let liveKeyboard = "live.keyboard"
    static let liveCalendar = "live.calendar"
    static let liveDiskSpace = "live.diskSpace"
    static let liveFocus = "live.focus"
    static let activityLinks = "activityLinks"
    static let gestures = "gestures"
    static let hotKey = "hotKey"
    static let floatingPlayer = "floatingPlayer"
    static let homeWidgets = "home.widgets"
    static let homeCounter = "home.counter"

    static func registerDefaults() {
        var defaults: [String: Any] = [
            // Before there was a choice, the island opened on hover unless that was turned off, and then on a click.
            openWith: UserDefaults.standard.object(forKey: "expandOnHover") as? Bool == false
                ? OpenWith.click.rawValue : OpenWith.hover.rawValue,
            hoverDelay: 0.12,
            hoverArea: HoverArea.near.rawValue,
            expandOnFileDrag: true,
            haptics: true,
            display: DisplayChoice.auto.rawValue,
            style: IslandStyle.auto.rawValue,
            material: IslandMaterial.glass.rawValue,
            idleBehavior: IdleBehavior.visible.rawValue,
            idleWidth: 150.0,
            idleHeight: 30.0,
            floatingGap: 3.0,
            menuOverhang: 8.0,
            artTint: true,
            clipboardLimit: 50,
            memoryLimit: 1024,
            notifyLinks: true,
            liveVolume: true,
            liveBrightness: true,
            hideSystemHUD: true,
            liveCharging: true,
            liveHeadphones: true,
            liveDrives: true,
            liveVPN: true,
            shakeBasket: true,
            liveTimers: true,
            liveClockApp: true,
            livePrivacy: true,
            liveDownloads: true,
            liveScreenshots: true,
            liveNetwork: true,
            liveDisplays: true,
            liveCapsLock: true,
            liveKeyboard: true,
            liveCalendar: true,
            liveDiskSpace: true,
            liveFocus: true,
            activityLinks: true,
            gestures: true,
            hotKey: true,
            floatingPlayer: false,
            homeWidgets: HomeWidget.save(HomeWidget.defaults),
        ]
        for tab in IslandTab.allCases { defaults[tab.prefKey] = true }
        UserDefaults.standard.register(defaults: defaults)
    }
}

enum DisplayChoice: String, CaseIterable, Identifiable {
    case auto, main, pointer
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return "Automatic (notched display first)"
        case .main: return "Main display"
        case .pointer: return "Follow the pointer"
        }
    }
}

enum IslandStyle: String, CaseIterable, Identifiable {
    case auto, notch, floating
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return "Automatic"
        case .notch: return "Attached to the top edge"
        case .floating: return "Floating capsule in the menu bar"
        }
    }
}

enum IslandMaterial: String, CaseIterable, Identifiable {
    case glass, solid
    var id: String { rawValue }
    var title: String { self == .glass ? "Dynamic Glass" : "Solid black" }
}

/// What opens the closed island. A click opens it with hover too.
enum OpenWith: String, CaseIterable, Identifiable {
    case hover, click, scroll
    var id: String { rawValue }
    var title: String {
        switch self {
        case .hover: return "Hovering over it"
        case .click: return "Clicking it"
        case .scroll: return "Scrolling over it"
        }
    }
    static var current: OpenWith {
        OpenWith(rawValue: UserDefaults.standard.string(forKey: Prefs.openWith) ?? "") ?? .hover
    }
}

/// How close the pointer has to come for the island to open.
enum HoverArea: String, CaseIterable, Identifiable {
    case near, on
    var id: String { rawValue }
    var title: String { self == .near ? "Near the island" : "On the island" }
    /// How far around the island the pointer counts, in points.
    var margin: CGFloat { self == .near ? 12 : 0 }
}

enum IdleBehavior: String, CaseIterable, Identifiable {
    case visible, hidden
    var id: String { rawValue }
    var title: String { self == .visible ? "Show a small pill" : "Hide until the pointer arrives" }
}
