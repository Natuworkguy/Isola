import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI

/// The pages of Settings, down the sidebar as in System Settings: each with its own coloured icon.
enum SettingsPage: String, CaseIterable, Identifiable {
    case general, island, look, activities, tray, clipboard, tools, notifications

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .island: return "Island"
        case .look: return "Look"
        case .activities: return "Live Activities"
        case .tray: return "File Tray"
        case .clipboard: return "Clipboard"
        case .tools: return "Tools"
        case .notifications: return "Notifications"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .island: return "capsule.portrait.fill"
        case .look: return "paintbrush.fill"
        case .activities: return "bolt.fill"
        case .tray: return "tray.full.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        case .tools: return "wand.and.stars"
        case .notifications: return "bell.badge.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: return .gray
        case .island: return .black
        case .look: return .pink
        case .activities: return .orange
        case .tray: return .blue
        case .clipboard: return .teal
        case .tools: return .purple
        case .notifications: return .red
        }
    }

    var blurb: String {
        switch self {
        case .general: return "Starting up, memory, updates."
        case .island: return "How the island opens, its tabs, gestures and keyboard."
        case .look: return "Where the island sits, and what it's made of."
        case .activities: return "What grows out of the island as it happens."
        case .tray: return "Files you keep at hand, and folders that fill it."
        case .clipboard: return "Everything you copy, kept to find again."
        case .tools: return "The Ring, capturing, dictation, windows, calls, the menu bar."
        case .notifications: return "Banners and Live Activities from other apps, and the lock screen."
        }
    }
}

/// A page's icon: its symbol on a soft rounded square, tinted with the page's colour. Quiet in the sidebar, where
/// only the chosen page's icon fills with colour.
struct SettingsIcon: View {
    let page: SettingsPage
    var size: CGFloat = 20
    var filled = true

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(filled ? AnyShapeStyle(page.tint.gradient) : AnyShapeStyle(Color.primary.opacity(0.06)))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: page.symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(filled ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .strokeBorder(.white.opacity(filled ? 0.18 : 0), lineWidth: 0.5)
            )
    }
}

extension SettingsPage {
    /// Words a search finds this page by, besides its title and blurb.
    var keywords: String {
        switch self {
        case .general: return "login start update memory welcome tour about quit"
        case .island: return "hover click scroll open gestures swipe keyboard shortcut tabs haptic lyrics words song media"
        case .look: return "display screen style notch floating glass black material width height gap artwork tint"
        case .activities: return "volume brightness charging battery headphones airpods bluetooth mouse keyboard trackpad controller drives vpn hud timer full screen"
        case .tray: return "files drag drop basket shake downloads folder convert zip pdf"
        case .clipboard: return "copy paste history pinned limit"
        case .tools: return "ring capture screenshot markup text ocr dictate snap windows calls mute menu bar"
        case .notifications: return "banner notify link lock screen activity"
        }
    }
}

struct SettingsView: View {
    @State private var page: SettingsPage = .general
    @State private var query = ""
    @Namespace private var selection

    private var pages: [SettingsPage] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return SettingsPage.allCases }
        return SettingsPage.allCases.filter {
            "\($0.title) \($0.blurb) \($0.keywords)".lowercased().contains(q)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 228)
                .background(VisualEffect(material: .sidebar).ignoresSafeArea())
            Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1).ignoresSafeArea()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 820, idealWidth: 860, minHeight: 600, idealHeight: 660)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Room for the window's buttons, which sit over the sidebar.
            Color.clear.frame(height: 40)
            HStack(spacing: 10) {
                IslandMark().frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Isola").font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("Version \(Updater.version)").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 14)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
                TextField("Search", text: $query).textFieldStyle(.plain).font(.system(size: 13))
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
            .padding(.horizontal, 12)
            .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(pages) { item in row(item) }
                    if pages.isEmpty {
                        Text("Nothing matches “\(query)”.")
                            .font(.callout).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10).padding(.top, 6)
                    }
                }
                .padding(.horizontal, 10)
            }
            .scrollIndicators(.never)

            Spacer(minLength: 0)
            HStack {
                Button { Onboarding.show() } label: { Label("Welcome tour", systemImage: "sparkles") }
                Spacer()
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .help("Quit Isola")
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .onChange(of: query) { _, _ in
            if let first = pages.first, !pages.contains(page) { page = first }
        }
    }

    private func row(_ item: SettingsPage) -> some View {
        let chosen = item == page
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { page = item }
        } label: {
            HStack(spacing: 10) {
                SettingsIcon(page: item, size: 22, filled: chosen)
                Text(item.title)
                    .font(.system(size: 13, weight: chosen ? .semibold : .regular))
                    .foregroundStyle(chosen ? .primary : .secondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .contentShape(Rectangle())
            .background {
                if chosen {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                        .matchedGeometryEffect(id: "chosen", in: selection)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var detail: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                SettingsIcon(page: page, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(page.title).font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text(page.blurb).font(.system(size: 12.5)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 32)
            .padding(.top, 34)
            .padding(.bottom, 6)

            if page == .island || page == .look || page == .general {
                IslandPreview()
                    .frame(height: 118)
                    .padding(.horizontal, 32)
                    .padding(.top, 12)
                    .padding(.bottom, 2)
            }

            Group {
                switch page {
                case .general: GeneralSettings()
                case .island: OpeningSettings()
                case .look: DisplaySettings()
                case .activities: ActivitySettings()
                case .tray: TraySettings()
                case .clipboard: ClipboardSettings()
                case .tools: ToolSettings()
                case .notifications: NotifySettings()
                }
            }
            .scrollContentBackground(.hidden)
            .id(page)
            .transition(.opacity.combined(with: .offset(y: 6)))
        }
        .animation(.easeOut(duration: 0.18), value: page)
    }
}

/// Isola's mark: a small island on a dark tile, glowing faintly.
struct IslandMark: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.06)], startPoint: .top, endPoint: .bottom))
            .overlay(
                Capsule().fill(.black)
                    .frame(width: 20, height: 7)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
                    .overlay(alignment: .trailing) { Circle().fill(.green).frame(width: 3, height: 3).padding(.trailing, 3) }
                    .offset(y: -7)
            )
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
    }
}

/// The island as the settings shape it: a strip of desktop with a menu bar, and the island at its top, its size,
/// style and material taken from the settings below as they change. It breathes open now and then, so you see both.
struct IslandPreview: View {
    @AppStorage(Prefs.style) private var style: IslandStyle = .auto
    @AppStorage(Prefs.material) private var material: IslandMaterial = .glass
    @AppStorage(Prefs.idleWidth) private var idleWidth = 150.0
    @AppStorage(Prefs.idleHeight) private var idleHeight = 30.0
    @AppStorage(Prefs.floatingGap) private var floatingGap = 3.0
    @State private var open = false
    private let beat = Timer.publish(every: 2.6, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            let scale = min(1, geo.size.width / 640)
            let floating = style == .floating
            let width = CGFloat(open ? 330 : idleWidth) * scale
            let height = CGFloat(open ? 84 : idleHeight) * scale
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.36, green: 0.42, blue: 0.78), Color(red: 0.86, green: 0.55, blue: 0.62),
                                        Color(red: 0.98, green: 0.78, blue: 0.58)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Rectangle().fill(.ultraThinMaterial).frame(height: 18)
                    .overlay(alignment: .leading) {
                        HStack(spacing: 10) {
                            Image(systemName: "apple.logo").font(.system(size: 9))
                            ForEach(["Finder", "File", "Edit", "View"], id: \.self) { Text($0).font(.system(size: 9, weight: .medium)) }
                        }
                        .foregroundStyle(Color.primary.opacity(0.7))
                        .padding(.leading, 12)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                islandShape(open: open, floating: floating)
                    .frame(width: width, height: height)
                    .overlay {
                        if open {
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 6).fill(LinearGradient(colors: [.orange, .pink], startPoint: .top, endPoint: .bottom))
                                    .frame(width: 34 * scale, height: 34 * scale)
                                VStack(alignment: .leading, spacing: 3) {
                                    Capsule().fill(.white.opacity(0.9)).frame(width: 90 * scale, height: 5)
                                    Capsule().fill(.white.opacity(0.4)).frame(width: 60 * scale, height: 4)
                                }
                                Spacer()
                                Image(systemName: "pause.fill").font(.system(size: 12 * scale)).foregroundStyle(.white)
                            }
                            .padding(.horizontal, 16 * scale)
                            .transition(.opacity)
                        }
                    }
                    .padding(.top, floating ? CGFloat(floatingGap) * scale + 2 : 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        }
        .onReceive(beat) { _ in withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) { open.toggle() } }
        .accessibilityLabel("Preview of the island")
    }

    @ViewBuilder
    private func islandShape(open: Bool, floating: Bool) -> some View {
        let radius: CGFloat = open ? 22 : 12
        let shape = UnevenRoundedRectangle(topLeadingRadius: floating ? radius : 0, bottomLeadingRadius: radius,
                                           bottomTrailingRadius: radius, topTrailingRadius: floating ? radius : 0,
                                           style: .continuous)
        if material == .glass {
            shape.fill(.black.opacity(0.55)).background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.2), lineWidth: 0.5))
        } else {
            shape.fill(.black)
        }
    }
}

/// An AppKit blur behind SwiftUI content.
struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) { view.material = material }
}

/// The File Tray: what drags do, and folders whose new files go into it.
struct TraySettings: View {
    @AppStorage(Prefs.expandOnFileDrag) private var expandOnFileDrag = true
    @AppStorage(Prefs.shakeBasket) private var shakeBasket = true
    @ObservedObject private var watched = WatchedFolders.shared

    var body: some View {
        Form {
            Section("Dragging") {
                Toggle("Open when dragging files toward it", isOn: $expandOnFileDrag)
                Toggle("Shake a dragged file to bring up the Basket", isOn: $shakeBasket)
                Text("The tray takes files, and things that aren't files yet: a message out of Mail, a picture from a web page or Photos.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Watched folders") {
                if watched.folders.isEmpty {
                    Text("None yet. New files in a watched folder go straight into the tray, like downloads as they finish.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(watched.folders, id: \.self) { folder in
                    HStack {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: folder.path)).resizable().frame(width: 18, height: 18)
                        Text(folder.lastPathComponent)
                        Text(folder.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button { watched.remove(folder) } label: { Image(systemName: "minus.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).help("Stop watching")
                    }
                }
                HStack {
                    Button("Add Folder…") { watched.choose() }
                    if !watched.folders.contains(FileActions.downloads) {
                        Button("Watch Downloads") { watched.add(FileActions.downloads) }
                    }
                }
            }
            Section("Actions") {
                Text("Right-click a file in the tray to convert it, shrink an image to send, or copy the text in it. The Actions button does it for everything: shrink the images, combine into one PDF, or zip.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// Isola's tools, each with its switch and its keys.
struct ToolSettings: View {
    @AppStorage(Prefs.toolRing) private var ring = true
    @AppStorage(Prefs.toolCapture) private var capture = true
    @AppStorage(Prefs.toolCaptureText) private var captureText = true
    @AppStorage(Prefs.toolDictate) private var dictate = true
    @AppStorage(Prefs.dictatePastes) private var dictatePastes = true
    @AppStorage(Prefs.toolSnap) private var snap = true
    @AppStorage(Prefs.toolMenuBar) private var menuBar = false
    @AppStorage(Prefs.liveCalls) private var calls = true
    @State private var trusted = AXIsProcessTrusted()

    var body: some View {
        Form {
            Section("The Ring") {
                tool("Ring of tools around the pointer", keys: Shortcuts.Action.ring.label, isOn: $ring)
                Text("Capture, copy text, dictate, pick a colour, open the tray or the clipboard, snap a window. Click one or press its number.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Screen") {
                tool("Capture an area and mark it up", keys: Shortcuts.Action.capture.label, isOn: $capture)
                tool("Copy the text in an area", keys: Shortcuts.Action.captureText.label, isOn: $captureText)
                Text("The first time, macOS asks to let Isola record the screen. Text is read on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Dictation") {
                tool("Dictate anywhere (again to stop)", keys: Shortcuts.Action.dictate.label, isOn: $dictate)
                Toggle("Type it where I was", isOn: $dictatePastes).disabled(!dictate)
                Text("What you say shows in the island as you say it, and goes on the clipboard. Typing it for you needs Accessibility.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Windows") {
                Toggle("Snap windows from the keyboard", isOn: $snap)
                if snap {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                        keysRow("Halves", "⌃⌥ ← → ↑ ↓")
                        keysRow("Fill the screen, centre", "⌃⌥↩  ⌃⌥C")
                        keysRow("Quarters", "⌃⌥ U I J K")
                        keysRow("Thirds", "⌃⌥ D F G")
                    }
                    .font(.callout)
                }
                if (snap || dictatePastes) && !trusted {
                    HStack {
                        Label("Needs Accessibility permission", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange).font(.caption)
                        Spacer()
                        Button("Open Settings") { MediaKeys.openAccessibilitySettings() }
                    }
                }
            }
            Section("Calls") {
                tool("Call timer, Mute and Leave in Zoom, Teams, FaceTime", keys: Shortcuts.Action.mute.label, isOn: $calls)
                Text("The shortcut mutes the Mac's own microphone, so it works whatever the app.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Menu bar") {
                Toggle("Hide menu bar icons behind a chevron", isOn: $menuBar)
                Text("⌘-drag icons to the left of Isola's divider to hide them; the chevron shows them for 15 seconds.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { trusted = AXIsProcessTrusted() }
    }

    private func tool(_ title: String, keys: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack {
                Text(title)
                Spacer()
                KeyCaps(keys)
            }
        }
    }

    private func keysRow(_ title: String, _ keys: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            KeyCaps(keys)
        }
    }
}

/// A shortcut written as keys on little caps.
struct KeyCaps: View {
    let keys: String
    init(_ keys: String) { self.keys = keys }

    var body: some View {
        Text(keys)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
    }
}

struct DisplaySettings: View {
    @AppStorage(Prefs.display) private var display: DisplayChoice = .auto
    @AppStorage(Prefs.style) private var style: IslandStyle = .auto
    @AppStorage(Prefs.material) private var material: IslandMaterial = .glass
    @AppStorage(Prefs.artTint) private var artTint = true
    @AppStorage(Prefs.idleBehavior) private var idleBehavior: IdleBehavior = .visible
    @AppStorage(Prefs.idleWidth) private var idleWidth = 150.0
    @AppStorage(Prefs.idleHeight) private var idleHeight = 30.0
    @AppStorage(Prefs.floatingGap) private var floatingGap = 3.0
    @AppStorage(Prefs.appleIsland) private var appleIsland = AppleIsland.auto
    @AppStorage(Prefs.menuOverhang) private var menuOverhang = 8.0
    @AppStorage(Prefs.hideInFullScreen) private var hideInFullScreen = true

    var body: some View {
        Form {
            Section("Where") {
                Toggle("Hide in full-screen apps and videos", isOn: $hideInFullScreen)
                Picker("Show island on", selection: $display) {
                    ForEach(DisplayChoice.allCases) { Text($0.title).tag($0) }
                }
                Picker("Style", selection: $style) {
                    ForEach(IslandStyle.allCases) { Text($0.title).tag($0) }
                }
                Picker("This Mac has Apple's Dynamic Island", selection: $appleIsland) {
                    ForEach(AppleIsland.allCases) { Text($0.title).tag($0) }
                }
                Text("On a MacBook with Apple's own Dynamic Island, Isola's island goes round its camera as a capsule, the same shape, and keeps out of sight when it has nothing to show, so Apple's is the one you see. Automatic tells it by the camera cutout's size.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Look") {
                Picker("Material", selection: $material) {
                    ForEach(IslandMaterial.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Tint with album artwork", isOn: $artTint)
                Text("Both materials work in every style: Dynamic Glass or solid black, floating in the menu bar or attached to the top edge. Around a MacBook's camera notch the closed island stays black, to blend with the notch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("No notch (iMac, Studio Display, external monitors)") {
                Picker("When idle", selection: $idleBehavior) {
                    ForEach(IdleBehavior.allCases) { Text($0.title).tag($0) }
                }
                slider("Idle width", value: $idleWidth, range: 80...260)
                slider("Idle height", value: $idleHeight, range: 20...44)
                slider("Gap from the top edge", value: $floatingGap, range: 0...12)
                slider("Overhang below the menu bar", value: $menuOverhang, range: 0...20)
            }
        }
        .formStyle(.grouped)
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title)
            Slider(value: value, in: range, step: 1)
            Text("\(Int(value.wrappedValue)) pt")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
        }
    }
}

struct OpeningSettings: View {
    @AppStorage(Prefs.lyrics) private var lyrics = false
    @AppStorage(Prefs.openWith) private var openWith: OpenWith = .hover
    @AppStorage(Prefs.hoverDelay) private var hoverDelay = 0.12
    @AppStorage(Prefs.hoverArea) private var hoverArea: HoverArea = .near
    @AppStorage(Prefs.clickOpens) private var clickOpens = true
    @AppStorage(Prefs.expandOnFileDrag) private var expandOnFileDrag = true
    @AppStorage(Prefs.shakeBasket) private var shakeBasket = true
    @AppStorage(Prefs.haptics) private var haptics = true
    @AppStorage(Prefs.clipboardLimit) private var clipboardLimit = 50
    @AppStorage(Prefs.notifyLinks) private var notifyLinks = true
    @AppStorage(Prefs.activityLinks) private var activityLinks = true
    @AppStorage(Prefs.activitiesOnly) private var activitiesOnly = false
    @AppStorage(Prefs.lockScreen) private var lockScreen = true
    @ObservedObject private var lock = LockScreen.shared
    @AppStorage(Prefs.liveVolume) private var liveVolume = true
    @AppStorage(Prefs.liveBrightness) private var liveBrightness = true
    @AppStorage(Prefs.hideSystemHUD) private var hideSystemHUD = true
    @ObservedObject private var mediaKeys = AppState.shared.mediaKeys
    @AppStorage(Prefs.liveCharging) private var liveCharging = true
    @AppStorage(Prefs.liveHeadphones) private var liveHeadphones = true
    @AppStorage(Prefs.liveDrives) private var liveDrives = true
    @AppStorage(Prefs.liveVPN) private var liveVPN = true

    var body: some View {
        Form {
            Section("Opening") {
                Toggle("Live Activities only", isOn: $activitiesOnly)
                Text(activitiesOnly
                     ? "The island never opens. It shows Live Activities and banners as they happen, and nothing in between."
                     : "Turn on to never open the island, and only show Live Activities and banners.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Open the island by", selection: $openWith) {
                    ForEach(OpenWith.allCases) { Text($0.title).tag($0) }
                }
                .disabled(activitiesOnly)
                Picker("Open when the pointer is", selection: $hoverArea) {
                    ForEach(HoverArea.allCases) { Text($0.title).tag($0) }
                }
                .disabled(openWith == .click || activitiesOnly)
                HStack {
                    Text("Hover delay")
                    Slider(value: $hoverDelay, in: 0...0.6, step: 0.02)
                    Text(String(format: "%.2fs", hoverDelay))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .trailing)
                }
                .disabled(openWith != .hover || activitiesOnly)
                Toggle("Clicking it opens it too", isOn: $clickOpens)
                    .disabled(openWith == .click || activitiesOnly)
                if openWith != .click && !clickOpens {
                    Text("A click on the closed island goes through to whatever is under it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Haptic tap when it opens", isOn: $haptics)
            }

            ShortcutSettings()

            Section("Media") {
                Toggle("Show the words of the song as it plays", isOn: $lyrics)
                Text("The line being sung shows under the artist. Isola asks LRCLIB, a free lyrics library, for the song's words, sending only its title, artist and length.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Tabs") {
                ForEach(IslandTab.allCases) { TabToggle(tab: $0) }
            }

        }
        .formStyle(.grouped)
    }
}

struct ActivitySettings: View {
    @AppStorage(Prefs.openWith) private var openWith: OpenWith = .hover
    @AppStorage(Prefs.hoverDelay) private var hoverDelay = 0.12
    @AppStorage(Prefs.hoverArea) private var hoverArea: HoverArea = .near
    @AppStorage(Prefs.clickOpens) private var clickOpens = true
    @AppStorage(Prefs.expandOnFileDrag) private var expandOnFileDrag = true
    @AppStorage(Prefs.shakeBasket) private var shakeBasket = true
    @AppStorage(Prefs.haptics) private var haptics = true
    @AppStorage(Prefs.clipboardLimit) private var clipboardLimit = 50
    @AppStorage(Prefs.notifyLinks) private var notifyLinks = true
    @AppStorage(Prefs.activityLinks) private var activityLinks = true
    @AppStorage(Prefs.activitiesOnly) private var activitiesOnly = false
    @AppStorage(Prefs.lockScreen) private var lockScreen = true
    @ObservedObject private var lock = LockScreen.shared
    @AppStorage(Prefs.liveVolume) private var liveVolume = true
    @AppStorage(Prefs.liveBrightness) private var liveBrightness = true
    @AppStorage(Prefs.hideSystemHUD) private var hideSystemHUD = true
    @ObservedObject private var mediaKeys = AppState.shared.mediaKeys
    @AppStorage(Prefs.liveCharging) private var liveCharging = true
    @AppStorage(Prefs.liveHeadphones) private var liveHeadphones = true
    @AppStorage(Prefs.liveDrives) private var liveDrives = true
    @AppStorage(Prefs.liveVPN) private var liveVPN = true

    var body: some View {
        Form {
            Section("Live Activities") {
                Toggle("Volume", isOn: $liveVolume)
                Toggle("Brightness", isOn: $liveBrightness)
                Toggle("Charging and low battery", isOn: $liveCharging)
                Toggle("Bluetooth devices connecting, with their battery, and running low", isOn: $liveHeadphones)
                Toggle("Drives, with an Eject button", isOn: $liveDrives)
                Toggle("VPN connecting and disconnecting", isOn: $liveVPN)
                Text("Headphones need Bluetooth permission the first time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            MoreActivitySettings()

            Section("macOS volume and brightness overlay") {
                Toggle("Hide it and show only Isola's bar", isOn: $hideSystemHUD)
                    .disabled(!liveVolume && !liveBrightness)
                if hideSystemHUD && mediaKeys.needsPermission {
                    HStack {
                        Label("Isola needs Accessibility permission", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        Spacer()
                        Button("Open Settings") { MediaKeys.openAccessibilitySettings() }
                    }
                }
                Text("Isola takes over the volume, mute and brightness keys, only for the ones switched on above, so the macOS overlay never appears. This needs Accessibility permission. Since Isola is not signed with a developer ID, you may need to grant it again after rebuilding.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        }
        .formStyle(.grouped)
    }
}

struct NotifySettings: View {
    @AppStorage(Prefs.openWith) private var openWith: OpenWith = .hover
    @AppStorage(Prefs.hoverDelay) private var hoverDelay = 0.12
    @AppStorage(Prefs.hoverArea) private var hoverArea: HoverArea = .near
    @AppStorage(Prefs.clickOpens) private var clickOpens = true
    @AppStorage(Prefs.expandOnFileDrag) private var expandOnFileDrag = true
    @AppStorage(Prefs.shakeBasket) private var shakeBasket = true
    @AppStorage(Prefs.haptics) private var haptics = true
    @AppStorage(Prefs.clipboardLimit) private var clipboardLimit = 50
    @AppStorage(Prefs.notifyLinks) private var notifyLinks = true
    @AppStorage(Prefs.activityLinks) private var activityLinks = true
    @AppStorage(Prefs.activitiesOnly) private var activitiesOnly = false
    @AppStorage(Prefs.lockScreen) private var lockScreen = true
    @ObservedObject private var lock = LockScreen.shared
    @AppStorage(Prefs.liveVolume) private var liveVolume = true
    @AppStorage(Prefs.liveBrightness) private var liveBrightness = true
    @AppStorage(Prefs.hideSystemHUD) private var hideSystemHUD = true
    @ObservedObject private var mediaKeys = AppState.shared.mediaKeys
    @AppStorage(Prefs.liveCharging) private var liveCharging = true
    @AppStorage(Prefs.liveHeadphones) private var liveHeadphones = true
    @AppStorage(Prefs.liveDrives) private var liveDrives = true
    @AppStorage(Prefs.liveVPN) private var liveVPN = true

    var body: some View {
        Form {
            Section("Notifications") {
                Toggle("Show banners from other apps and scripts", isOn: $notifyLinks)
                Text("Anything can show a banner in the island by opening an isola://notify link, for example:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(verbatim: "open -g \"isola://notify?title=Done&text=Build%20finished&color=green\"")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                Toggle("Let apps and scripts show Live Activities", isOn: $activityLinks)
                Text("An isola://activity link starts a Live Activity with a checklist that updates in place, and ends it:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(verbatim: "open -g \"isola://activity?id=build&title=Build&steps=done:Fetch|active:Compile|todo:Test\"\nopen -g \"isola://activity/end?id=build\"")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }

            Section("Lock screen") {
                Toggle("Show Live Activities on the lock screen", isOn: $lockScreen)
                Text("While the Mac is locked, each Live Activity from an app or script (like Flash at work) is a notification that updates as it goes, and says when it finished. Unlocking clears them, and so does turning this off. It is in the menu bar menu too.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if lockScreen {
                    HStack {
                        if lock.allowed == false {
                            Label("Notifications are off for Isola, so nothing can show while locked.",
                                  systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Spacer()
                            Button("Open System Settings") { lock.openSystemSettings() }
                        } else {
                            Text(lock.trying ? "Lock your Mac now (Control-Command-Q): one shows in a few seconds."
                                 : "Shows one in a few seconds: lock your Mac to see it there.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Try it") { lock.tryIt() }
                                .disabled(lock.trying)
                        }
                    }
                    if !lock.lastSeen.isEmpty {
                        Text(lock.lastSeen)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

        }
        .formStyle(.grouped)
        .onAppear { lock.check() }
    }
}

struct ClipboardSettings: View {
    @AppStorage(Prefs.openWith) private var openWith: OpenWith = .hover
    @AppStorage(Prefs.hoverDelay) private var hoverDelay = 0.12
    @AppStorage(Prefs.hoverArea) private var hoverArea: HoverArea = .near
    @AppStorage(Prefs.clickOpens) private var clickOpens = true
    @AppStorage(Prefs.expandOnFileDrag) private var expandOnFileDrag = true
    @AppStorage(Prefs.shakeBasket) private var shakeBasket = true
    @AppStorage(Prefs.haptics) private var haptics = true
    @AppStorage(Prefs.clipboardLimit) private var clipboardLimit = 50
    @AppStorage(Prefs.notifyLinks) private var notifyLinks = true
    @AppStorage(Prefs.activityLinks) private var activityLinks = true
    @AppStorage(Prefs.activitiesOnly) private var activitiesOnly = false
    @AppStorage(Prefs.lockScreen) private var lockScreen = true
    @ObservedObject private var lock = LockScreen.shared
    @AppStorage(Prefs.liveVolume) private var liveVolume = true
    @AppStorage(Prefs.liveBrightness) private var liveBrightness = true
    @AppStorage(Prefs.hideSystemHUD) private var hideSystemHUD = true
    @ObservedObject private var mediaKeys = AppState.shared.mediaKeys
    @AppStorage(Prefs.liveCharging) private var liveCharging = true
    @AppStorage(Prefs.liveHeadphones) private var liveHeadphones = true
    @AppStorage(Prefs.liveDrives) private var liveDrives = true
    @AppStorage(Prefs.liveVPN) private var liveVPN = true

    var body: some View {
        Form {
            Section("Clipboard") {
                Stepper("Keep \(clipboardLimit) items", value: $clipboardLimit, in: 10...200, step: 10)
                Text("Copies from password managers are never recorded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// Swipes on the island and the keyboard shortcut.
struct ShortcutSettings: View {
    @AppStorage(Prefs.gestures) private var gestures = true
    @AppStorage(Prefs.hotKey) private var hotKey = true

    var body: some View {
        Section("Gestures and keyboard") {
            Toggle("Swipe down on the island to open it, up on its top edge to close it", isOn: $gestures)
            Text("Swiping sideways over the music skips to the next or previous track. A mouse wheel works too.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Open and close the island with \(HotKey.description)", isOn: $hotKey)
        }
    }
}

/// The Live Activities beyond volume, battery and devices, each with its own switch, and the permissions some need.
struct MoreActivitySettings: View {
    @AppStorage(Prefs.liveTimers) private var timers = true
    @AppStorage(Prefs.liveClockApp) private var clockApp = true
    @AppStorage(Prefs.livePrivacy) private var privacy = true
    @AppStorage(Prefs.liveDownloads) private var downloads = true
    @AppStorage(Prefs.liveScreenshots) private var screenshots = true
    @AppStorage(Prefs.liveNetwork) private var network = true
    @AppStorage(Prefs.liveDisplays) private var displays = true
    @AppStorage(Prefs.liveCapsLock) private var capsLock = true
    @AppStorage(Prefs.liveKeyboard) private var keyboard = true
    @AppStorage(Prefs.liveCalendar) private var calendar = true
    @AppStorage(Prefs.liveDiskSpace) private var diskSpace = true
    @AppStorage(Prefs.liveFocus) private var focus = true
    @State private var trusted = AXIsProcessTrusted()
    @State private var focusReadable = SystemActivities.currentFocus() != nil

    var body: some View {
        Section("More Live Activities") {
            Toggle("Timers ring in the island, with Stop and Repeat", isOn: $timers)
            Toggle("Alarms and timers from the Clock app", isOn: $clockApp)
            if clockApp && !trusted {
                permission("The Clock app needs Accessibility permission") { MediaKeys.openAccessibilitySettings() }
            }
            Toggle("Camera and microphone in use, with privacy dots", isOn: $privacy)
            Toggle("Downloads finishing", isOn: $downloads)
            Toggle("Screenshots and screen recordings saved", isOn: $screenshots)
            Toggle("Going offline and coming back", isOn: $network)
            Toggle("Displays connecting", isOn: $displays)
            Toggle("Caps Lock", isOn: $capsLock)
            Toggle("Keyboard layout changing", isOn: $keyboard)
            Toggle("Meetings five minutes before they start", isOn: $calendar)
            Toggle("Running low on storage", isOn: $diskSpace)
            Toggle("Focus turning on and off", isOn: $focus)
            if focus && !focusReadable {
                permission("Focus needs Full Disk Access") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            Text("macOS gives apps no way to read other apps' notifications or the current Focus. So Clock alerts use Accessibility: Isola reads the Clock banner, moves it out of sight and presses its buttons for you, though on some macOS versions it can still flash for a moment. Focus reads the Focus database, which needs Full Disk Access. Downloads and screenshots ask once for those folders, and meetings use the calendar access you give the Calendar tab.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            trusted = AXIsProcessTrusted()
            focusReadable = SystemActivities.currentFocus() != nil
        }
    }

    private func permission(_ text: String, open: @escaping () -> Void) -> some View {
        HStack {
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
            Spacer()
            Button("Open Settings", action: open)
        }
    }
}

struct TabToggle: View {
    let tab: IslandTab
    @AppStorage private var enabled: Bool

    init(tab: IslandTab) {
        self.tab = tab
        _enabled = AppStorage(wrappedValue: true, tab.prefKey)
    }

    var body: some View {
        Toggle(isOn: $enabled) {
            Label(tab.rawValue, systemImage: tab.symbol)
        }
    }
}

struct GeneralSettings: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @AppStorage(Prefs.memoryLimit) private var memoryLimit = 1024
    @AppStorage(Prefs.checkUpdates) private var checkUpdates = true
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Memory") {
                Picker("Memory limit", selection: $memoryLimit) {
                    Text("512 MB").tag(512)
                    Text("1 GB").tag(1024)
                    Text("2 GB").tag(2048)
                    Text("4 GB").tag(4096)
                    Text("No limit").tag(0)
                }
                Text("If Isola ever uses more than this, it clears its caches, and if that is not enough, restarts itself, so it can never slow your Mac down.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Updates") {
                Toggle("Check for a new version every day", isOn: $checkUpdates)
                HStack {
                    Text(updater.status.isEmpty ? "You have Isola \(Updater.version)." : updater.status)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let newer = updater.newer {
                        Button("Get \(newer.version)") { NSWorkspace.shared.open(newer.page) }
                            .buttonStyle(.borderedProminent)
                    }
                    Button("Check Now") { updater.check() }
                }
            }

            Section("About") {
                LabeledContent("Isola", value: "Version \(Updater.version)")
                LabeledContent("Made by", value: "Natuworkguy")
                Button("Show the Welcome Tour") { Onboarding.show() }
            }
        }
        .formStyle(.grouped)
    }
}
