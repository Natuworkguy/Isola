import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI

/// The welcome tour, the first time Isola starts (and from Settings, General): what the island does, the shortcuts
/// worth knowing, the permissions some features need, and starting at login.
enum Onboarding {
    private static var window: NSWindow?

    static func show() {
        if let window {
            DockPresence.show(window)
            return
        }
        let made = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 620, height: 470),
                            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        made.titlebarAppearsTransparent = true
        made.titleVisibility = .hidden
        made.isMovableByWindowBackground = true
        made.isReleasedWhenClosed = false
        made.contentView = NSHostingView(rootView: OnboardingView { close() })
        made.center()
        made.title = "Welcome to Isola"
        window = made
        DockPresence.show(made)
    }

    static func close() {
        UserDefaults.standard.set(true, forKey: Prefs.onboarded)
        window?.close()
        window = nil
    }
}

struct OnboardingView: View {
    let done: () -> Void
    @State private var step = 0
    @State private var trusted = AXIsProcessTrusted()
    @State private var screen = CGPreflightScreenCaptureAccess()
    @State private var atLogin = SMAppService.mainApp.status == .enabled
    private let steps = 4
    private let tick = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch step {
                case 0: welcome
                case 1: tryThese
                case 2: permissions
                default: finish
                }
            }
            .id(step)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 44)
            .padding(.top, 36)

            HStack {
                HStack(spacing: 7) {
                    ForEach(0..<steps, id: \.self) { i in
                        Capsule().fill(i == step ? Color.accentColor : Color.primary.opacity(0.15))
                            .frame(width: i == step ? 18 : 7, height: 7)
                    }
                }
                Spacer()
                if step > 0 {
                    Button("Back") { go(step - 1) }
                }
                Button(step == steps - 1 ? "Start Using Isola" : "Continue") {
                    step == steps - 1 ? done() : go(step + 1)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
        }
        .frame(width: 620, height: 470)
        .onReceive(tick) { _ in
            trusted = AXIsProcessTrusted()
            screen = CGPreflightScreenCaptureAccess()
        }
    }

    private func go(_ to: Int) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { step = to }
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            ZStack {
                Capsule().fill(.black).frame(width: 220, height: 58)
                    .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                HStack(spacing: 10) {
                    Circle().fill(LinearGradient(colors: [.pink, .orange], startPoint: .top, endPoint: .bottom))
                        .frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Welcome to Isola").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                        Text("Your notch, but useful").font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    Image(systemName: "waveform").foregroundStyle(.pink)
                }
                .padding(.horizontal, 14)
                .frame(width: 220)
            }
            .padding(.top, 14)
            Text("Hello.").font(.system(size: 34, weight: .bold, design: .rounded))
            Text("Isola lives at the top of your screen, round the notch, or as a capsule on a Mac without one. Move the pointer to it to open it: music, files, your clipboard, your calendar, and what's going on, as it happens.")
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)
        }
    }

    private var tryThese: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Things to try").font(.system(size: 26, weight: .bold, design: .rounded))
            tip("tray.and.arrow.down.fill", .blue, "Drag a file to the top of the screen",
                "It drops into the File Tray, to drag back out later. Shake it while dragging for the Basket.")
            tip("circle.hexagongrid.fill", .purple, "Press ⌃⌥Space for the Ring",
                "Capture, copy text off the screen, dictate, pick a colour, snap windows.")
            tip("camera.viewfinder", .teal, "Press ⌃⌥⇧S to capture and mark up",
                "Arrows, boxes, blur, text, then copy it or drop it in the tray.")
            tip("rectangle.split.2x1.fill", .orange, "Press ⌃⌥ and an arrow to snap a window",
                "Halves, quarters with U I J K, thirds with D F G, ⌃⌥↩ to fill.")
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("A few permissions").font(.system(size: 26, weight: .bold, design: .rounded))
            Text("Only for the features that need them. Isola never sends anything anywhere.")
                .foregroundStyle(.secondary)
            permission("hand.raised.fill", .blue, "Accessibility",
                       "Snapping windows, typing what you dictate, and Isola's own volume and brightness overlay.",
                       granted: trusted) {
                let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
                _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
            }
            permission("rectangle.dashed.badge.record", .purple, "Screen Recording",
                       "Capturing part of the screen to mark up or read its text.", granted: screen) {
                _ = CGRequestScreenCaptureAccess()
            }
            Text("The microphone, speech recognition and your calendar are asked for the first time you use them.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var finish: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 54))
                .foregroundStyle(.green.gradient)
            Text("You're set.").font(.system(size: 30, weight: .bold, design: .rounded))
            Text("Everything can be changed in Settings: the gear in the island, or Isola's menu bar icon.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Toggle("Open Isola when I log in", isOn: $atLogin)
                .toggleStyle(.switch)
                .onChange(of: atLogin) { _, on in
                    try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    atLogin = SMAppService.mainApp.status == .enabled
                }
                .padding(.top, 6)
        }
    }

    private func tip(_ symbol: String, _ tint: Color, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.gradient)
                .frame(width: 36, height: 36)
                .overlay(Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    private func permission(_ symbol: String, _ tint: Color, _ title: String, _ text: String, granted: Bool,
                            ask: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.gradient)
                .frame(width: 36, height: 36)
                .overlay(Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.callout)
            } else {
                Button("Allow…", action: ask)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))
    }
}
