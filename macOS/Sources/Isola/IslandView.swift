import SwiftUI

struct IslandView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let size = state.currentSize
        let floating = state.isFloating
        let peeked = state.isExpanded || state.banner != nil ? nil : state.peekedActivity
        let hasBanner = (state.banner != nil || peeked != nil) && !state.isExpanded
        let radius: CGFloat = state.isExpanded ? 36 : (hasBanner ? 26 : (floating ? size.height / 2 : 12))
        let topRadius: CGFloat = floating ? radius : 0
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: topRadius,
            bottomLeadingRadius: radius,
            bottomTrailingRadius: radius,
            topTrailingRadius: topRadius,
            style: .continuous
        )
        // Glass in every style, floating or attached to the top edge. Only around a MacBook's camera notch does the
        // closed island stay black, so it blends with the notch itself.
        let glassOn = state.useGlass && (state.isExpanded || hasBanner || !state.onHardwareNotch)
        let showRim = state.isExpanded || floating || hasBanner || glassOn
        let shadow = AppState.shadow(expanded: state.isExpanded || hasBanner, floating: floating || glassOn)
        // Attached to the top edge, the island's top is the edge of the screen. The glass is drawn taller so its
        // edge highlights fall above the screen, and the rim leaves the top edge out, so neither marks the corners.
        let bleed: CGFloat = floating ? 0 : 40

        ZStack(alignment: .top) {
            Color.black.opacity(glassOn ? 0 : 1)
            AmbientGlow(monitor: state.nowPlaying, active: state.isExpanded && state.tintFromArt)

            if state.isExpanded {
                ExpandedView()
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            } else if let banner = state.banner {
                BannerView(banner: banner, topInset: state.bannerInset)
                    .transition(.opacity)
            } else if let peeked {
                ActivityCard(activity: peeked, topInset: state.bannerInset)
                    .transition(.opacity)
            } else if let hud = state.hud {
                HUDView(hud: hud, notchGap: state.notchGap)
                    .transition(.opacity)
            } else {
                CollapsedView(monitor: state.nowPlaying)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(alignment: .top) {
            LiquidGlassLayer(shape: shape)
                .frame(width: size.width, height: size.height + bleed)
                .offset(y: -bleed)
                .opacity(glassOn ? 1 : 0)
        }
        .clipShape(shape)
        .overlay(
            shape
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(glassOn ? 0.55 : 0.16), .white.opacity(0.04), .white.opacity(glassOn ? 0.2 : 0.07)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .mask(alignment: .top) { Rectangle().padding(.top, floating ? 0 : 1.5) }
                .opacity(showRim ? 1 : 0)
        )
        .background(
            // Drawn only outside the island. A plain .shadow also showed through the translucent glass.
            shape.fill(Color.black)
                .shadow(color: .black.opacity(shadow.opacity), radius: shadow.radius, y: shadow.y)
                .clipShape(OutsideShape(inner: shape), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)
        )
        .opacity(state.hiddenWhenIdle && !state.isExpanded ? 0 : 1)
        // At launch the island waits above the top edge of the screen, then slides down into place.
        .offset(y: state.arrived ? 0 : -(size.height + AppState.maxShadowReach))
        .contentShape(shape)
        .onTapGesture {
            // A tap on a banner or card puts it away. A tap on an activity with steps shows its card; anywhere else
            // opens the island, unless it opens by scrolling.
            if state.banner != nil && !state.isExpanded {
                state.dismissBanner()
            } else if peeked != nil {
                state.dismissPeek()
            } else if !state.isExpanded, let activity = state.compactActivity, !activity.steps.isEmpty {
                state.peekActivity(activity.id, for: 8)
            } else if !state.isExpanded, OpenWith.current != .scroll {
                state.isExpanded = true
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: state.banner)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: state.peekID)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: state.isExpanded)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: state.collapsedSize)
        .animation(.easeInOut(duration: 0.3), value: glassOn)
        .animation(.easeInOut(duration: 0.3), value: state.hiddenWhenIdle)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Everything around the island, so its shadow can be clipped to the outside.
struct OutsideShape: Shape {
    var inner: UnevenRoundedRectangle

    var animatableData: UnevenRoundedRectangle.AnimatableData {
        get { inner.animatableData }
        set { inner.animatableData = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path(rect.insetBy(dx: -AppState.maxShadowReach, dy: -AppState.maxShadowReach))
        path.addPath(inner.path(in: rect))
        return path
    }
}

struct LiquidGlassLayer: View {
    let shape: UnevenRoundedRectangle

    var body: some View {
        ZStack {
            base
            shape.fill(Color.black.opacity(0.34))
            shape.fill(
                LinearGradient(
                    colors: [.white.opacity(0.18), .white.opacity(0.03), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
            )
            shape.fill(
                RadialGradient(
                    colors: [.white.opacity(0.10), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 260
                )
            )
        }
    }

    @ViewBuilder private var base: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.clear, in: shape)
        } else {
            VisualEffectBlur()
        }
        #else
        VisualEffectBlur()
        #endif
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .vibrantDark)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct AmbientGlow: View {
    @ObservedObject var monitor: NowPlayingMonitor
    let active: Bool

    var body: some View {
        ZStack {
            RadialGradient(colors: [monitor.tint.opacity(0.55), .clear], center: .bottomLeading, startRadius: 0, endRadius: 340)
            RadialGradient(colors: [monitor.tint.opacity(0.28), .clear], center: .topTrailing, startRadius: 0, endRadius: 260)
        }
        .blur(radius: 24)
        .opacity(active && monitor.hasTrack ? 1 : 0)
        .animation(.easeInOut(duration: 0.8), value: monitor.tint)
        .animation(.easeInOut(duration: 0.5), value: active)
        .allowsHitTesting(false)
    }
}
