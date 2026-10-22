import AppKit
import Combine
import SwiftUI

final class NotchPanel: NSPanel {
    var allowsKey = false
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}

final class NotchController {
    private let state: AppState
    private let panel: NotchPanel
    private let defaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()
    private var pollTimer: Timer?
    private var collapseAt: Date?
    private var hoverSince: Date?
    private var currentScreen: NSScreen?
    private var floatingGap: CGFloat = 8
    private var scrollMonitor: Any?
    private var globalScrollMonitor: Any?
    private var swipe = CGPoint.zero
    private var swipeFired = false
    private var lastScroll = Date.distantPast
    /// After a swipe closes the island, hovering waits for the pointer to leave before it can open it again.
    private var hoverBlocked = false

    private lazy var searchPanel: NotchPanel = {
        let search = NotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        search.allowsKey = true
        search.isFloatingPanel = true
        search.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        search.backgroundColor = .clear
        search.isOpaque = false
        search.hasShadow = false
        search.hidesOnDeactivate = false
        search.animationBehavior = .none
        search.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        search.contentView = NSHostingView(rootView: SearchFieldView().environmentObject(state))
        return search
    }()

    // Drag tracking, for opening on a file drag and for the shake that brings up the Basket.
    private var buttonDown = false
    private var idleDragCount = NSPasteboard(name: .drag).changeCount
    private var dragStartCount = 0
    private var shakeSamples: [(x: CGFloat, time: TimeInterval)] = []
    private var shookThisDrag = false

    init(state: AppState) {
        self.state = state
        panel = NotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // The panel is mostly empty space; tick() lets the pointer through everywhere but the island.
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: IslandView().environmentObject(state))
    }

    func show() {
        refresh(immediate: true)
        panel.orderFrontRegardless()

        state.$isExpanded.combineLatest(state.$hasLiveActivity)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in self?.refresh(immediate: false) }
            .store(in: &cancellables)

        state.$banner
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh(immediate: false) }
            .store(in: &cancellables)

        state.$keyboardFocus
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] wanted in self?.setKeyboard(wanted) }
            .store(in: &cancellables)

        state.$isExpanded
            .filter { !$0 }
            .sink { [weak self] _ in self?.state.keyboardFocus = false }
            .store(in: &cancellables)

        state.$searchFieldRect
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.placeSearchPanel() }
            .store(in: &cancellables)

        state.$hud
            .map { $0 != nil }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh(immediate: false) }
            .store(in: &cancellables)

        state.nowPlaying.$isPlaying.combineLatest(state.$activities, state.$privacy)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playing, activities, privacy in
                self?.state.hasLiveActivity = playing || !activities.isEmpty || !privacy.isEmpty
            }
            .store(in: &cancellables)

        state.$peekID.combineLatest(state.$activities)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                DispatchQueue.main.async { self?.refresh(immediate: false) }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh(immediate: true) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.refresh(immediate: true) }
            .store(in: &cancellables)

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            return self.handleScroll(event) ? nil : event
        }
        // Scrolls next to the island go to the app underneath, so they are watched from outside too. Set to open by
        // scrolling, one near the closed island opens it.
        globalScrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, !self.state.isExpanded, OpenWith.current == .scroll,
                  self.closedArea().contains(NSEvent.mouseLocation) else { return }
            _ = self.handleScroll(event)
        }

        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func hasNotch(_ screen: NSScreen) -> Bool {
        screen.safeAreaInsets.top > 0 && screen.auxiliaryTopLeftArea != nil && screen.auxiliaryTopRightArea != nil
    }

    private func screenUnderPointer() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.insetBy(dx: -0.5, dy: -0.5).contains(point) }
    }

    private func pickScreen() -> NSScreen {
        let screens = NSScreen.screens
        switch DisplayChoice(rawValue: defaults.string(forKey: Prefs.display) ?? "") ?? .auto {
        case .pointer: return screenUnderPointer() ?? screens[0]
        case .main: return screens[0]
        case .auto: return screens.first { hasNotch($0) } ?? screens[0]
        }
    }

    private func refresh(immediate: Bool) {
        var screen = pickScreen()
        if state.isExpanded, let current = currentScreen, NSScreen.screens.contains(current) { screen = current }
        currentScreen = screen

        let notched = hasNotch(screen)
        let style = IslandStyle(rawValue: defaults.string(forKey: Prefs.style) ?? "") ?? .auto
        let floating = style == .floating || (style == .auto && !notched)
        let hardware = notched && !floating

        let idleWidth = max(CGFloat(defaults.double(forKey: Prefs.idleWidth)), 60)
        let idleHeight = max(CGFloat(defaults.double(forKey: Prefs.idleHeight)), 20)
        let activity = state.hasLiveActivity
        let hudActive = state.hud != nil
        let ears = AppState.earWidth * 2
        let notchWidth = hardware
            ? screen.frame.width - (screen.auxiliaryTopLeftArea?.width ?? 0) - (screen.auxiliaryTopRightArea?.width ?? 0)
            : 0

        let collapsed: CGSize
        if hardware {
            let width = hudActive ? notchWidth + AppState.hudEarWidth * 2 : notchWidth + (activity ? ears : 0)
            collapsed = CGSize(width: width, height: screen.safeAreaInsets.top)
        } else {
            let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
            let topGap = CGFloat(defaults.double(forKey: Prefs.floatingGap))
            let overhang = CGFloat(defaults.double(forKey: Prefs.menuOverhang))
            let height = (floating && menuBar > 0) ? max(menuBar - topGap + overhang, 18) : idleHeight
            let width = hudActive ? max(idleWidth, 220) : (activity ? max(idleWidth, ears + 70) : idleWidth)
            collapsed = CGSize(width: width, height: height)
        }

        let bannerActive = state.banner != nil
        let inset = hardware ? collapsed.height : 0
        let shown: CGSize
        if let banner = state.banner {
            let buttons = (banner.action == nil ? 0 : 1) + (banner.secondAction == nil ? 0 : 1)
            shown = CGSize(width: max(collapsed.width, buttons > 1 ? 440 : (buttons == 1 ? 380 : 340)),
                           height: inset + AppState.bannerContentHeight)
        } else if let peeked = state.peekedActivity {
            shown = CGSize(width: max(collapsed.width, 400), height: inset + ActivityCard.height(for: peeked))
        } else {
            shown = collapsed
        }
        floatingGap = CGFloat(defaults.double(forKey: Prefs.floatingGap))
        let hideIdle = IdleBehavior(rawValue: defaults.string(forKey: Prefs.idleBehavior) ?? "") == .hidden

        state.isFloating = floating
        state.onHardwareNotch = hardware
        state.bannerInset = hardware ? collapsed.height : 0
        state.notchGap = notchWidth
        state.collapsedSize = shown
        state.contentTopInset = hardware ? collapsed.height + 2 : (floating ? 14 : idleHeight + 4)
        state.hiddenWhenIdle = !hardware && hideIdle && !activity && !bannerActive && !hudActive && state.peekID == nil
        state.useGlass = IslandMaterial(rawValue: defaults.string(forKey: Prefs.material) ?? "") != .solid
        state.tintFromArt = defaults.bool(forKey: Prefs.artTint)

        let enabled = IslandTab.allCases.filter { defaults.bool(forKey: $0.prefKey) }
        state.enabledTabs = enabled.isEmpty ? [.media] : enabled
        if !state.enabledTabs.contains(state.tab) { state.tab = state.enabledTabs[0] }

        applyFrame()
    }

    private func islandRect(expanded: Bool) -> NSRect {
        let screen = currentScreen ?? pickScreen()
        let size = expanded ? AppState.expandedSize : state.collapsedSize
        let top = screen.frame.maxY - (state.isFloating ? floatingGap : 0)
        return NSRect(x: screen.frame.midX - size.width / 2, y: top - size.height,
                      width: size.width, height: size.height)
    }

    /// One fixed size that holds every state of the island and its shadow. Resizing the window while SwiftUI
    /// animated made the island vanish for a few frames and then grow from the middle, because AppKit and SwiftUI
    /// do not resize in the same frame. Now the window only moves when the screen or the settings change.
    private func panelRect() -> NSRect {
        let screen = currentScreen ?? pickScreen()
        let reach = AppState.maxShadowReach
        let width = AppState.expandedSize.width + reach * 2
        let height = AppState.expandedSize.height + reach
        let top = screen.frame.maxY - (state.isFloating ? floatingGap : 0)
        return NSRect(x: screen.frame.midX - width / 2, y: top - height, width: width, height: height)
    }

    /// The search field's own window takes the keyboard while searching. Hiding it when search closes hands typing
    /// straight back to the app underneath, the way Spotlight does, without touching the island's window: hiding and
    /// re-showing that made the whole island flash.
    private func setKeyboard(_ wanted: Bool) {
        if wanted {
            placeSearchPanel()
            searchPanel.orderFrontRegardless()
            searchPanel.makeKey()
        } else {
            searchPanel.orderOut(nil)
        }
    }

    private func placeSearchPanel() {
        let rect = state.searchFieldRect
        guard state.keyboardFocus, rect.width > 0, rect.height > 0 else { return }
        let frame = NSRect(x: panel.frame.minX + rect.minX, y: panel.frame.maxY - rect.maxY,
                           width: rect.width, height: rect.height)
        if searchPanel.frame != frame { searchPanel.setFrame(frame, display: true) }
    }

    private func applyFrame() {
        let rect = panelRect()
        if panel.frame != rect { panel.setFrame(rect, display: true) }
    }
}

extension NotchController {
    fileprivate func tick() {
        let point = NSEvent.mouseLocation
        trackDrag(point)

        // Clicks, hovers and drops only belong to the island; everywhere else in the panel they pass through.
        let interactive = state.isExpanded
            ? islandRect(expanded: true).insetBy(dx: -4, dy: -4)
            : islandRect(expanded: false).insetBy(dx: -12, dy: -12)
        let passThrough = !interactive.contains(point)
        if panel.ignoresMouseEvents != passThrough { panel.ignoresMouseEvents = passThrough }

        if !state.isExpanded,
           DisplayChoice(rawValue: defaults.string(forKey: Prefs.display) ?? "") == .pointer,
           let under = screenUnderPointer(), under != currentScreen {
            refresh(immediate: true)
            return
        }

        if state.isExpanded {
            handleOpenIsland(point)
        } else {
            handleClosedIsland(point)
        }
    }

    private func handleOpenIsland(_ point: NSPoint) {
        hoverSince = nil
        let zone = islandRect(expanded: true).insetBy(dx: -24, dy: -24)
        if state.heldOpen {
            // Opened from the keyboard: normal hover rules start once the pointer has been there.
            if zone.contains(point) { state.heldOpen = false }
            collapseAt = nil
            return
        }
        if state.isPinned || state.keyboardFocus || state.editingHome || zone.contains(point) {
            collapseAt = nil
        } else if let at = collapseAt {
            if Date() >= at {
                collapseAt = nil
                withAnimation { state.isExpanded = false }
            }
        } else {
            collapseAt = Date().addingTimeInterval(0.35)
        }
    }

    private func handleClosedIsland(_ point: NSPoint) {
        collapseAt = nil
        let hot = islandRect(expanded: false).insetBy(dx: -12, dy: -12)
        guard hot.contains(point) else {
            hoverSince = nil
            hoverBlocked = false
            return
        }
        guard !hoverBlocked else { return }

        if NSEvent.pressedMouseButtons & 1 != 0 {
            if defaults.bool(forKey: Prefs.expandOnFileDrag), draggingFiles() { open(tab: .tray) }
        } else if OpenWith.current == .hover, state.banner == nil {
            // (A banner stays up under the pointer, which is probably on its way to click it or its button.)
            guard closedArea().contains(point) else {
                hoverSince = nil
                return
            }
            let since = hoverSince ?? Date()
            hoverSince = since
            if Date().timeIntervalSince(since) >= defaults.double(forKey: Prefs.hoverDelay) { open(tab: nil) }
        }
    }

    /// Where the pointer counts as at the closed island. Near, it only has to come close; on, it has to be over the
    /// island itself. Aiming at the top of the screen, the pointer runs on to its edge, so above the island counts too.
    private func closedArea() -> NSRect {
        let margin = (HoverArea(rawValue: defaults.string(forKey: Prefs.hoverArea) ?? "") ?? .near).margin
        var area = islandRect(expanded: false).insetBy(dx: -margin, dy: -margin)
        if let screen = currentScreen { area.size.height = max(area.height, screen.frame.maxY - area.minY) }
        return area
    }

    fileprivate func open(tab: IslandTab?) {
        hoverSince = nil
        if let tab, state.enabledTabs.contains(tab) { state.tab = tab }
        withAnimation { state.isExpanded = true }
        if defaults.bool(forKey: Prefs.haptics) {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    /// Opens or closes the island from the keyboard shortcut.
    func toggleFromKeyboard() {
        if state.isExpanded {
            state.heldOpen = false
            withAnimation { state.isExpanded = false }
        } else {
            state.heldOpen = true
            open(tab: nil)
        }
    }

    /// Trackpad swipes on the island: two fingers down opens it, up (on its top edge) closes it, and sideways skips
    /// to the next or previous track while music plays. A mouse wheel works too. Set to open by scrolling, a scroll
    /// either way opens it, gestures or not. True when the swipe was used.
    fileprivate func handleScroll(_ event: NSEvent) -> Bool {
        let gestures = defaults.bool(forKey: Prefs.gestures)
        let scrollOpens = !state.isExpanded && OpenWith.current == .scroll
        guard gestures || scrollOpens, event.momentumPhase.isEmpty else { return false }
        if event.phase == .began || Date().timeIntervalSince(lastScroll) > 0.35 {
            swipe = .zero
            swipeFired = false
        }
        lastScroll = Date()
        // Measured as the fingers move: down and right are positive, whatever the scrolling direction setting.
        let flip: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
        let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
        swipe.x += event.scrollingDeltaX * flip * scale
        swipe.y += event.scrollingDeltaY * flip * scale
        guard !swipeFired else { return false }
        let vertical = abs(swipe.y) > abs(swipe.x)
        let media = state.nowPlaying
        if !state.isExpanded {
            if vertical && (swipe.y > 24 || scrollOpens && swipe.y < -24) {
                swipeFired = true
                open(tab: nil)
                return true
            }
            if gestures && !vertical && abs(swipe.x) > 40 && media.isPlaying {
                swipeFired = true
                swipe.x < 0 ? media.next() : media.previous()
                return true
            }
            return false
        }
        let island = islandRect(expanded: true)
        let onTopEdge = NSEvent.mouseLocation.y > island.maxY - state.contentTopInset - 46
        if vertical && swipe.y < -30 && onTopEdge && !state.isPinned && !state.editingHome {
            swipeFired = true
            hoverBlocked = true
            state.heldOpen = false
            withAnimation { state.isExpanded = false }
            return true
        }
        if !vertical && abs(swipe.x) > 40 && state.tab == .media && media.hasTrack {
            swipeFired = true
            swipe.x < 0 ? media.next() : media.previous()
            return true
        }
        return false
    }

    /// The drag pasteboard keeps whatever was dragged last, so a file drag only counts if the pasteboard changed
    /// after the button went down. Otherwise dragging a window would look like dragging the last file again.
    fileprivate func draggingFiles() -> Bool {
        let pasteboard = NSPasteboard(name: .drag)
        return buttonDown && pasteboard.changeCount != dragStartCount && pasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
    }

    private func trackDrag(_ point: NSPoint) {
        let down = NSEvent.pressedMouseButtons & 1 != 0
        if !down {
            if buttonDown { state.basket.dragEnded() }
            buttonDown = false
            idleDragCount = NSPasteboard(name: .drag).changeCount
            return
        }
        if !buttonDown {
            // The count from just before the press: a drag that started within this tick still counts as new.
            buttonDown = true
            dragStartCount = idleDragCount
            shakeSamples = []
            shookThisDrag = false
        }
        guard !shookThisDrag, defaults.bool(forKey: Prefs.shakeBasket), draggingFiles() else { return }
        if detectShake(point) {
            shookThisDrag = true
            state.basket.show(at: point)
        }
    }

    /// A shake is the pointer swinging left and right at least three times, 30pt or more each way, within 0.8s.
    private func detectShake(_ point: NSPoint) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        shakeSamples.append((point.x, now))
        shakeSamples.removeAll { now - $0.time > 0.8 }
        guard let first = shakeSamples.first else { return false }

        var direction: CGFloat = 0
        var extreme = first.x
        var reversals = 0
        for sample in shakeSamples.dropFirst() {
            if direction == 0 {
                if abs(sample.x - extreme) >= 30 {
                    direction = sample.x > extreme ? 1 : -1
                    extreme = sample.x
                }
            } else if (sample.x - extreme) * direction > 0 {
                extreme = sample.x
            } else if abs(sample.x - extreme) >= 30 {
                reversals += 1
                direction = -direction
                extreme = sample.x
            }
        }
        return reversals >= 3
    }
}
