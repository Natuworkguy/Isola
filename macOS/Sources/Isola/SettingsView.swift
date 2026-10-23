import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            DisplaySettings()
                .tabItem { Label("Display", systemImage: "display") }
            IslandSettings()
                .tabItem { Label("Island", systemImage: "capsule.portrait") }
        }
        .frame(width: 520, height: 620)
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
    @AppStorage(Prefs.menuOverhang) private var menuOverhang = 8.0

    var body: some View {
        Form {
            Section("Where") {
                Picker("Show island on", selection: $display) {
                    ForEach(DisplayChoice.allCases) { Text($0.title).tag($0) }
                }
                Picker("Style", selection: $style) {
                    ForEach(IslandStyle.allCases) { Text($0.title).tag($0) }
                }
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

struct IslandSettings: View {
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
                Picker("Open the island by", selection: $openWith) {
                    ForEach(OpenWith.allCases) { Text($0.title).tag($0) }
                }
                Picker("Open when the pointer is", selection: $hoverArea) {
                    ForEach(HoverArea.allCases) { Text($0.title).tag($0) }
                }
                .disabled(openWith == .click)
                HStack {
                    Text("Hover delay")
                    Slider(value: $hoverDelay, in: 0...0.6, step: 0.02)
                    Text(String(format: "%.2fs", hoverDelay))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .trailing)
                }
                .disabled(openWith != .hover)
                Toggle("Clicking it opens it too", isOn: $clickOpens)
                    .disabled(openWith == .click)
                if openWith != .click && !clickOpens {
                    Text("A click on the closed island goes through to whatever is under it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Open when dragging files toward it", isOn: $expandOnFileDrag)
                Toggle("Shake a dragged file to bring up the Basket", isOn: $shakeBasket)
                Toggle("Haptic tap when it opens", isOn: $haptics)
            }

            ShortcutSettings()

            Section("Tabs") {
                ForEach(IslandTab.allCases) { TabToggle(tab: $0) }
            }

            Section("Live Activities") {
                Toggle("Volume", isOn: $liveVolume)
                Toggle("Brightness", isOn: $liveBrightness)
                Toggle("Charging and low battery", isOn: $liveCharging)
                Toggle("Headphones and AirPods connecting", isOn: $liveHeadphones)
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

            Section("About") {
                LabeledContent("Isola", value: "Version 0.3.0")
                LabeledContent("Made by", value: "Natuworkguy")
            }
        }
        .formStyle(.grouped)
    }
}
