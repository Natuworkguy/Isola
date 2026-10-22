import SwiftUI

struct BlurFade: ViewModifier {
    let radius: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content.blur(radius: radius).opacity(opacity)
    }
}

extension AnyTransition {
    static var blurFade: AnyTransition {
        .modifier(active: BlurFade(radius: 10, opacity: 0), identity: BlurFade(radius: 0, opacity: 1))
    }
}

struct ExpandedView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 12) {
            Spacer().frame(height: state.contentTopInset)

            ZStack {
                TabBar()
                HStack(spacing: 6) {
                    if state.tab == .home {
                        IconButton(symbol: "pencil", active: state.editingHome) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { state.editingHome.toggle() }
                        }
                        .help(state.editingHome ? "Done" : "Arrange widgets")
                        .transition(.scale.combined(with: .opacity))
                    }
                    Spacer()
                    IconButton(symbol: state.isPinned ? "pin.fill" : "pin", active: state.isPinned) {
                        state.isPinned.toggle()
                    }
                    IconButton(symbol: "gearshape", active: false) {
                        NotificationCenter.default.post(name: .isolaOpenSettings, object: nil)
                    }
                }
                .padding(.horizontal, 22)
            }

            ZStack {
                switch state.tab {
                case .home: HomeView()
                case .media: NowPlayingView(monitor: state.nowPlaying)
                case .tray: TrayView(tray: state.tray)
                case .clipboard: ClipboardView(monitor: state.clipboard)
                case .calendar: CalendarView(monitor: state.calendar)
                case .system: SystemView(stats: state.system)
                }
            }
            .id(state.tab)
            .transition(.blurFade)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 30)
            .padding(.bottom, 24)
            .animation(.smooth(duration: 0.35), value: state.tab)
        }
        .foregroundStyle(.white)
    }
}

struct TabBar: View {
    @EnvironmentObject var state: AppState
    @Namespace private var glide

    var body: some View {
        HStack(spacing: 2) {
            ForEach(state.enabledTabs) { tab in
                let selected = state.tab == tab
                Button {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.76)) { state.tab = tab }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.symbol)
                        if selected {
                            Text(tab.rawValue)
                                .transition(.opacity.combined(with: .scale(scale: 0.7, anchor: .leading)))
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selected ? Color.black : Color.white.opacity(0.72))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background {
                        if selected {
                            Capsule()
                                .fill(Color.white)
                                .shadow(color: .white.opacity(0.35), radius: 8)
                                .matchedGeometryEffect(id: "highlight", in: glide)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.1)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
    }
}

struct IconButton: View {
    let symbol: String
    let active: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(active ? Color.black : Color.white.opacity(hovering ? 1 : 0.7))
                .frame(width: 26, height: 26)
                .background(Circle().fill(active ? Color.white : Color.white.opacity(hovering ? 0.2 : 0.1)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// The closed island's ears: a Live Activity if one outranks the music, otherwise the album art and an equaliser,
/// with the privacy dots at the far right whenever something uses the camera, microphone or screen.
struct CollapsedView: View {
    @ObservedObject var monitor: NowPlayingMonitor
    @EnvironmentObject var state: AppState

    var body: some View {
        let dots = !state.shownPrivacy.isEmpty
        HStack(spacing: 0) {
            if let activity = state.compactActivity {
                ActivityGlyph(activity: activity)
                    .frame(width: AppState.earWidth)
                Spacer(minLength: 0)
                ActivityTrailing(activity: activity)
                    .padding(.trailing, dots ? 8 : 0)
                    .frame(width: AppState.earWidth)
            } else if monitor.isPlaying {
                ArtworkView(image: monitor.artwork, icon: monitor.sourceIcon, size: 20, radius: 5)
                    .frame(width: AppState.earWidth)
                Spacer(minLength: 0)
                EqualizerView(color: monitor.tint)
                    .padding(.trailing, dots ? 6 : 0)
                    .frame(width: AppState.earWidth)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxHeight: .infinity)
        .overlay(alignment: .trailing) {
            if dots {
                PrivacyDots(indicators: state.shownPrivacy)
                    .padding(.trailing, 7)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .transition(.opacity)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: state.compactActivity?.id)
    }
}

struct ArtworkView: View {
    let image: NSImage?
    var icon: NSImage? = nil
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [.pink, .purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(placeholder)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    @ViewBuilder private var placeholder: some View {
        if let icon {
            Image(nsImage: icon).resizable().scaledToFit().padding(size * 0.18)
        } else {
            Image(systemName: "play.fill")
                .font(.system(size: size * 0.4))
                .foregroundStyle(Color.white.opacity(0.9))
        }
    }
}

struct EqualizerView: View {
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4, id: \.self) { index in
                    let phase = sin(t * 5.5 + Double(index) * 1.4)
                    Capsule()
                        .fill(color)
                        .frame(width: 3, height: 5 + 11 * CGFloat((phase + 1) / 2))
                }
            }
            .frame(width: 18, height: 16)
        }
    }
}
