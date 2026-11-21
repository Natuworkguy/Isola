import AppKit
import AVFoundation
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
        let made = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 860, height: 580),
                            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        made.titlebarAppearsTransparent = true
        made.titleVisibility = .hidden
        made.isMovableByWindowBackground = true
        made.isReleasedWhenClosed = false
        // Always dark: the film and the type are made for it, as Apple's own welcome screens are.
        made.appearance = NSAppearance(named: .darkAqua)
        made.backgroundColor = .black
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
    @State private var forward = true
    @State private var trusted = AXIsProcessTrusted()
    @State private var screen = CGPreflightScreenCaptureAccess()
    @State private var atLogin = SMAppService.mainApp.status == .enabled
    private let steps = 4
    private let tick = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()
    static let ease = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.7)

    var body: some View {
        ZStack {
            // The film, made in Riptide: the island opening into a music card and a charging pill, over a drifting
            // wallpaper. Full bright on the first page, frosted behind the others.
            // It only plays on the first page; behind the others it holds still, frosted.
            LoopingVideo(name: "Welcome", playing: step == 0).ignoresSafeArea()
            Rectangle().fill(.ultraThinMaterial).opacity(step == 0 ? 0 : 1).ignoresSafeArea()
            LinearGradient(colors: [.clear, .black.opacity(step == 0 ? 0.75 : 0.45)], startPoint: .center, endPoint: .bottom)
                .ignoresSafeArea()

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
                .transition(.asymmetric(
                    insertion: .offset(x: forward ? 60 : -60).combined(with: .opacity).combined(with: .blurIn),
                    removal: .offset(x: forward ? -60 : 60).combined(with: .opacity).combined(with: .blurIn)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.horizontal, 56)
                .padding(.top, 48)

                bar
            }
        }
        .foregroundStyle(.white)
        .frame(width: 860, height: 580)
        .animation(Self.ease, value: step)
        .onReceive(tick) { _ in
            trusted = AXIsProcessTrusted()
            screen = CGPreflightScreenCaptureAccess()
        }
    }

    private var bar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                ForEach(0..<steps, id: \.self) { i in
                    Capsule().fill(.white.opacity(i <= step ? 0.95 : 0.22))
                        .frame(width: i == step ? 28 : 8, height: 4)
                }
            }
            Text(String(format: "%02d / %02d", step + 1, steps))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            if step > 0 {
                Button("Back") { go(step - 1) }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 10)
            }
            PillButton(title: step == steps - 1 ? "Start using Isola" : "Continue") {
                step == steps - 1 ? done() : go(step + 1)
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 56)
        .padding(.top, 22)
        .padding(.bottom, 30)
    }

    private func go(_ to: Int) {
        forward = to > step
        withAnimation(Self.ease) { step = to }
    }

    // MARK: pages

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("Welcome to Isola", delay: 0.05)
            Reveal(delay: 0.12) { Headline("Your notch,", size: 76) }
            Reveal(delay: 0.22) {
                Headline("but alive.", size: 76)
                    .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.62, blue: 0.42), Color(red: 1, green: 0.38, blue: 0.62),
                                                              Color(red: 0.62, green: 0.5, blue: 1)],
                                                     startPoint: .leading, endPoint: .trailing))
            }
            Reveal(delay: 0.34) {
                Text("Music, files, your clipboard, your calendar and what your Mac is doing, at the top of the screen. Point at it to open it.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineSpacing(3)
                    .frame(maxWidth: 440, alignment: .leading)
                    .padding(.top, 18)
            }
        }
    }

    private var tryThese: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow("Four things to try", delay: 0.05)
                Reveal(delay: 0.1) { Headline("Try these first.", size: 52) }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                tip(1, "Drag a file to the top of the screen", "It drops into the File Tray. Shake it as you drag for the Basket.", keys: nil)
                tip(2, "The Ring of tools", "Capture, copy text, dictate, pick a colour, snap a window.", keys: "⌃⌥Space")
                tip(3, "Capture and mark up", "Arrows, boxes, blur and text, then copy it or keep it.", keys: "⌃⌥⇧S")
                tip(4, "Snap a window", "Halves with the arrows, quarters with U I J K, thirds with D F G.", keys: "⌃⌥ ←")
            }
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow("Permissions", delay: 0.05)
                Reveal(delay: 0.1) { Headline("Two switches.", size: 52) }
                Reveal(delay: 0.16) {
                    Text("Only for the tools that need them. Nothing you do in Isola leaves this Mac.")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.65))
                        .padding(.top, 6)
                }
            }
            VStack(spacing: 10) {
                permission(0, "hand.raised.fill", "Accessibility",
                           "Snapping windows, typing what you dictate, and Isola's own volume and brightness bars.",
                           granted: trusted) {
                    let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
                    _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
                }
                permission(1, "rectangle.dashed.badge.record", "Screen Recording",
                           "Capturing part of the screen to mark it up or read its text.", granted: screen) {
                    _ = CGRequestScreenCaptureAccess()
                }
            }
            Reveal(delay: 0.4) {
                Text("The microphone, speech and your calendar are asked for the first time you use them.")
                    .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    private var finish: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("All done", delay: 0.05)
            Reveal(delay: 0.12) {
                Headline("You're set.", size: 92)
                    .foregroundStyle(LinearGradient(colors: [.white, Color(red: 1, green: 0.75, blue: 0.62)],
                                                     startPoint: .top, endPoint: .bottom))
            }
            Reveal(delay: 0.24) {
                Text("Change anything in Settings: the gear in the island, or Isola's icon in the menu bar.")
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: 460, alignment: .leading)
                    .padding(.top, 14)
            }
            Reveal(delay: 0.34) {
                Toggle(isOn: $atLogin) {
                    Text("Open Isola when I log in").font(.system(size: 13, weight: .semibold))
                }
                .toggleStyle(.switch)
                .onChange(of: atLogin) { _, on in
                    try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    atLogin = SMAppService.mainApp.status == .enabled
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Glass(radius: 14))
                .padding(.top, 26)
            }
        }
    }

    // MARK: pieces

    private func tip(_ n: Int, _ title: String, _ text: String, keys: String?) -> some View {
        Reveal(delay: 0.16 + Double(n) * 0.06) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(String(format: "%02d", n))
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    if let keys { KeyCaps(keys).foregroundStyle(.white) }
                }
                Text(title).font(.system(size: 14, weight: .bold))
                Text(text).font(.system(size: 12)).foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
            .background(Glass(radius: 18))
        }
    }

    private func permission(_ i: Int, _ symbol: String, _ title: String, _ text: String, granted: Bool,
                            ask: @escaping () -> Void) -> some View {
        Reveal(delay: 0.24 + Double(i) * 0.08) {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(.white.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .bold))
                    Text(text).font(.system(size: 12)).foregroundStyle(.white.opacity(0.62))
                }
                Spacer()
                if granted {
                    Label("Allowed", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    PillButton(title: "Allow", small: true, action: ask)
                }
            }
            .padding(14)
            .background(Glass(radius: 16))
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: granted)
        }
    }
}

/// Heavy display type, tight as a poster's.
private struct Headline: View {
    let text: String
    let size: CGFloat
    init(_ text: String, size: CGFloat) { self.text = text; self.size = size }
    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .black))
            .tracking(-size * 0.035)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .shadow(color: .black.opacity(0.18), radius: 20, y: 8)
    }
}

/// The small label over a headline: spaced capitals, set in mono.
private struct Eyebrow: View {
    let text: String
    let delay: Double
    init(_ text: String, delay: Double) { self.text = text; self.delay = delay }
    var body: some View {
        Reveal(delay: delay) {
            HStack(spacing: 8) {
                Capsule().fill(.white).frame(width: 18, height: 2)
                Text(text.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(2.4)
            }
            .foregroundStyle(.white.opacity(0.8))
            .padding(.bottom, 10)
        }
    }
}

/// Comes in once, a beat after the page: up a little, out of a blur, into focus.
private struct Reveal<Content: View>: View {
    let delay: Double
    @ViewBuilder let content: Content
    @State private var shown = false
    var body: some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 18)
            .blur(radius: shown ? 0 : 10)
            .onAppear { withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.9).delay(delay)) { shown = true } }
    }
}

/// Frosted glass with a hairline edge, lighter at the top as if lit from above.
private struct Glass: View {
    let radius: CGFloat
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape.fill(.ultraThinMaterial)
            .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.10), .white.opacity(0.02)], startPoint: .top, endPoint: .bottom)))
            .overlay(shape.stroke(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom), lineWidth: 0.8))
    }
}

/// White capsule, black type: the one thing on the page to press. It gives a little under the pointer.
private struct PillButton: View {
    let title: String
    var small = false
    let action: () -> Void
    @State private var hovering = false
    @State private var pressed = false
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: small ? 12 : 14, weight: .bold))
                .foregroundStyle(.black)
                .padding(.horizontal, small ? 16 : 24)
                .frame(height: small ? 30 : 40)
                .background(Capsule().fill(.white))
                .shadow(color: .white.opacity(hovering ? 0.35 : 0), radius: 16)
                .scaleEffect(pressed ? 0.95 : hovering ? 1.03 : 1)
        }
        .buttonStyle(.plain)
        .onHover { inside in withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { hovering = inside } }
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in withAnimation(.easeOut(duration: 0.1)) { pressed = true } }
            .onEnded { _ in withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { pressed = false } })
    }
}

private struct BlurModifier: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View { content.blur(radius: radius) }
}

extension AnyTransition {
    /// Out of focus as it comes and goes.
    static var blurIn: AnyTransition {
        .modifier(active: BlurModifier(radius: 14), identity: BlurModifier(radius: 0))
    }
}

/// A film from the app's resources, playing on a loop with no sound, filling its frame.
struct LoopingVideo: NSViewRepresentable {
    let name: String
    var playing = true

    final class PlayerView: NSView {
        private let player = AVQueuePlayer()
        private var looper: AVPlayerLooper?
        private let layerOfPlayer = AVPlayerLayer()

        init(url: URL?) {
            super.init(frame: .zero)
            wantsLayer = true
            layer = CALayer()
            layer?.backgroundColor = NSColor.black.cgColor
            layerOfPlayer.player = player
            layerOfPlayer.videoGravity = .resizeAspectFill
            layer?.addSublayer(layerOfPlayer)
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            if let url {
                looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            }
        }

        required init?(coder: NSCoder) { nil }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layerOfPlayer.frame = bounds
            CATransaction.commit()
        }

        var playing = true {
            didSet { if playing != oldValue { apply() } }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        /// Plays while it is wanted and on screen; otherwise holds the frame it is on.
        private func apply() {
            playing && window != nil ? player.play() : player.pause()
        }
    }

    func makeNSView(context: Context) -> PlayerView {
        PlayerView(url: Bundle.main.url(forResource: name, withExtension: "mp4"))
    }

    func updateNSView(_ view: PlayerView, context: Context) { view.playing = playing }
}
