import AppKit
import SwiftUI

/// A button on a banner, for Isola's own banners only (isola://notify banners never get one).
struct BannerAction {
    let title: String
    let symbol: String
    let perform: () -> Void
}

/// A short message the collapsed island grows to show, then shrinks back.
struct IslandBanner: Identifiable, Equatable {
    let id = UUID()
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String
    var action: BannerAction? = nil
    /// A second, quieter button, such as Snooze beside Stop.
    var secondAction: BannerAction? = nil
    /// An alarm or timer going off: the icon shakes like a bell until the banner goes.
    var ringing = false
    /// Runs however the banner goes: a button, a tap, its time running out or another banner taking its place.
    var onDismiss: (() -> Void)? = nil

    static func == (lhs: IslandBanner, rhs: IslandBanner) -> Bool { lhs.id == rhs.id }
}

/// A Live Activity that stays in the island while it runs: a timer counting down, a call, an app's progress. The
/// highest priority one sits in the ears beside the notch, and one with steps grows into a card when it changes.
struct LiveActivity: Identifiable, Equatable {
    struct Step: Equatable {
        enum State: String { case done, active, pending, failed }
        var text: String
        var state: State
    }

    let id: String
    var symbol: String
    var tint: Color
    var title: String
    var subtitle = ""
    /// Short text for the right ear, such as "2/5", when it is not counting.
    var trailing = ""
    /// Counts down to this moment in the right ear, like a timer.
    var endsAt: Date?
    /// Counts up from this moment in the right ear, like a stopwatch.
    var since: Date?
    var progress: Double?
    var steps: [Step] = []
    /// A conversation, as it goes: who said what, oldest first.
    var lines: [Line] = []
    /// Media playing counts as 1: an activity above that takes the ears from it.
    var priority = 2
    /// What it is doing with the microphone. Anything but off stands in for Isola's own microphone dot and banner.
    var mic: Mic = .off

    /// On: it is using the microphone. Listening: waiting for you to speak. Talking: hearing you now.
    enum Mic: String { case off, on, listening, talking }

    struct Line: Equatable {
        var speaker: String
        var text: String
    }
}

/// The coloured dots that say something is using the camera, the microphone or the screen.
enum PrivacyIndicator: String, CaseIterable, Comparable {
    case camera, microphone, screen

    var color: Color {
        switch self {
        case .camera: return .green
        case .microphone: return .orange
        case .screen: return .purple
        }
    }

    static func < (lhs: PrivacyIndicator, rhs: PrivacyIndicator) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

enum IslandTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case media = "Media"
    case tray = "File Tray"
    case clipboard = "Clipboard"
    case calendar = "Calendar"
    case system = "System"

    var id: String { rawValue }
    var prefKey: String { "tab." + rawValue }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .media: return "play.rectangle"
        case .tray: return "tray.full"
        case .clipboard: return "doc.on.clipboard"
        case .calendar: return "calendar"
        case .system: return "cpu"
        }
    }
}

final class AppState: ObservableObject {
    static let shared = AppState()
    static let expandedSize = CGSize(width: 640, height: 290)
    static let earWidth: CGFloat = 50
    /// Each ear's width while volume or brightness shows beside the notch: icon on the left, bar and number right.
    static let hudEarWidth: CGFloat = 104
    /// Room for a banner's content: below the notch on notched screens, the whole banner everywhere else.
    static let bannerContentHeight: CGFloat = 56

    @Published var isExpanded = false
    @Published var isPinned = false
    /// Opened from the keyboard: stays open until the pointer has visited it, or the shortcut is pressed again.
    @Published var heldOpen = false
    @Published var tab: IslandTab = .home
    /// True while the Home tab is being arranged: the island stays open, as if pinned.
    @Published var editingHome = false
    @Published var isDropTargeted = false

    @Published var collapsedSize = CGSize(width: 150, height: 30)
    @Published var isFloating = false
    /// True when the island sits around a MacBook's camera notch.
    @Published var onHardwareNotch = false
    @Published var contentTopInset: CGFloat = 34
    @Published var hiddenWhenIdle = false
    @Published var hasLiveActivity = false
    @Published var enabledTabs: [IslandTab] = IslandTab.allCases
    @Published var useGlass = true
    @Published var tintFromArt = true
    @Published var banner: IslandBanner?
    /// False until the island has slid down into place at launch.
    @Published var arrived = false
    /// Space at the top of a banner that the camera notch covers. Zero on screens without one.
    @Published var bannerInset: CGFloat = 0
    @Published var hud: IslandHUD?
    /// Live Activities that stay while they run, newest first.
    @Published var activities: [LiveActivity] = []
    /// The activity grown into a card for a moment, after it changed or was clicked.
    @Published var peekID: String?
    @Published var privacy: Set<PrivacyIndicator> = []
    /// True while the clipboard search is open. The island itself never takes the keyboard: the search field lives in
    /// a small window of its own over the search bar, so clicking the island never steals typing from another app.
    @Published var keyboardFocus = false
    @Published var clipboardQuery = ""
    /// Where the search field sits, in the island window's coordinates (top-left origin).
    @Published var searchFieldRect: CGRect = .zero
    /// Width of the camera notch the collapsed island sits around. Zero on screens without one.
    @Published var notchGap: CGFloat = 0

    let clipboard = ClipboardMonitor()
    let nowPlaying = NowPlayingMonitor()
    let tray = FileTray()
    let calendar = CalendarMonitor()
    let system = SystemStats()
    let live = LiveActivities()
    let systemActivities = SystemActivities()
    let mediaKeys = MediaKeys()
    let basket = Basket()
    private var hudDismiss: DispatchWorkItem?
    private var peekDismiss: DispatchWorkItem?

    var currentSize: CGSize { isExpanded ? Self.expandedSize : collapsedSize }

    /// How far the island's shadow can reach past its edges (blur radius twice, plus offset). The panel keeps this
    /// much room around the open island, or the window edge would cut the shadow off into a visible rectangle.
    static let maxShadowReach: CGFloat = 48

    static func shadow(expanded: Bool, floating: Bool) -> (opacity: Double, radius: CGFloat, y: CGFloat) {
        if expanded { return (0.4, 18, 10) }
        return floating ? (0.22, 5, 2) : (0, 0, 0)
    }

    func showBanner(_ banner: IslandBanner, for seconds: TimeInterval) {
        if let old = self.banner, old.id != banner.id { old.onDismiss?() }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { self.banner = banner }
        if UserDefaults.standard.bool(forKey: Prefs.haptics) {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard self?.banner?.id == banner.id else { return }
            self?.dismissBanner()
        }
    }

    /// Shows volume or brightness in the ears; each new change keeps it up a little longer.
    func showHUD(_ hud: IslandHUD) {
        if self.hud == nil {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { self.hud = hud }
        } else {
            self.hud = hud
        }
        hudDismiss?.cancel()
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { self?.hud = nil }
        }
        hudDismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }

    func dismissBanner() {
        banner?.onDismiss?()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { banner = nil }
    }

    // MARK: Live Activities

    /// The activity shown in the ears, or nil for media (or nothing).
    var compactActivity: LiveActivity? {
        var best: LiveActivity?
        for activity in activities where activity.priority > (best?.priority ?? Int.min) { best = activity }
        guard let best else { return nil }
        return nowPlaying.isPlaying && best.priority <= 1 ? nil : best
    }

    var peekedActivity: LiveActivity? {
        guard let peekID else { return nil }
        return activities.first { $0.id == peekID }
    }

    /// Starts an activity, or updates the one with the same id in place.
    func setActivity(_ activity: LiveActivity, peek: Bool = false) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            if let index = activities.firstIndex(where: { $0.id == activity.id }) {
                activities[index] = activity
            } else {
                activities.insert(activity, at: 0)
            }
        }
        if peek { peekActivity(activity.id) }
    }

    func activity(_ id: String) -> LiveActivity? {
        activities.first { $0.id == id }
    }

    func endActivity(_ id: String) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            activities.removeAll { $0.id == id }
            if peekID == id { peekID = nil }
        }
    }

    /// Grows the activity into its card for a few seconds.
    func peekActivity(_ id: String, for seconds: TimeInterval = 5) {
        guard activities.contains(where: { $0.id == id }) else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { peekID = id }
        peekDismiss?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard self?.peekID == id else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { self?.peekID = nil }
        }
        peekDismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func dismissPeek() {
        peekDismiss?.cancel()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { peekID = nil }
    }

    /// Whether a Live Activity already shows the microphone in use, so Isola's own dot and banner stay away.
    var microphoneShown: Bool { activities.contains { $0.mic != .off } }

    /// The privacy dots to show: the microphone's only when no Live Activity shows it already.
    var shownPrivacy: Set<PrivacyIndicator> {
        microphoneShown ? privacy.subtracting([.microphone]) : privacy
    }

    func setPrivacy(_ indicator: PrivacyIndicator, _ on: Bool) {
        guard privacy.contains(indicator) != on else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            if on { privacy.insert(indicator) } else { privacy.remove(indicator) }
        }
    }
}
