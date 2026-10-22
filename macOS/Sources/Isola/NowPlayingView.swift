import SwiftUI

struct NowPlayingView: View {
    @ObservedObject var monitor: NowPlayingMonitor
    @ObservedObject private var floating = FloatingPlayer.shared
    @State private var scrubFraction: Double?

    var body: some View {
        if monitor.players.count > 1 {
            PlayerStack(monitor: monitor)
        } else if monitor.hasTrack {
            HStack(spacing: 24) {
                ArtworkView(image: monitor.artwork, icon: monitor.sourceIcon, size: 132, radius: 20)
                    .shadow(color: monitor.tint.opacity(0.55), radius: 24, y: 8)
                    .scaleEffect(monitor.isPlaying ? 1 : 0.94)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: monitor.isPlaying)

                VStack(alignment: .leading, spacing: 3) {
                    sourceChip
                    Text(monitor.title)
                        .font(.system(size: 20, weight: .bold))
                        .lineLimit(1)
                    Text(monitor.artist)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    scrubber
                        .disabled(monitor.isBackground)
                    HStack {
                        Text(Self.format(displayPosition))
                        Spacer()
                        Text("-" + Self.format(max(monitor.duration - displayPosition, 0)))
                    }
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))

                    HStack(spacing: 30) {
                        control("backward.fill", 17, monitor.previous)
                        control(monitor.isPlaying ? "pause.fill" : "play.fill", 25, monitor.togglePlayPause)
                        control("forward.fill", 17, monitor.next)
                    }
                    // A background player cannot be reached by the Mac's media commands.
                    .disabled(monitor.isBackground)
                    .opacity(monitor.isBackground ? 0.35 : 1)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
                }
                .frame(maxWidth: 300)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) { popOutButton }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "music.note.list").font(.system(size: 30))
                Text("Nothing playing").font(.system(size: 15, weight: .semibold))
                Text("Play music or a video in any app.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .foregroundStyle(.white.opacity(0.8))
        }
    }

    /// The music in a window of its own, anywhere on the desktop.
    private var popOutButton: some View {
        Button { floating.toggle() } label: {
            Image(systemName: floating.isShown ? "pip.exit" : "pip.enter")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(floating.isShown ? 0.9 : 0.55))
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(floating.isShown ? "Close the floating player" : "Open the floating player")
    }

    @ViewBuilder private var sourceChip: some View {
        if !monitor.sourceName.isEmpty {
            HStack(spacing: 5) {
                if let icon = monitor.sourceIcon {
                    Image(nsImage: icon).resizable().frame(width: 12, height: 12)
                }
                Text(monitor.isBackground ? "\(monitor.sourceName) · in the background" : monitor.sourceName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(0.12)))
            .padding(.bottom, 3)
        }
    }

    private var displayPosition: Double {
        if let scrubFraction { return scrubFraction * monitor.duration }
        return monitor.position
    }

    private var fraction: Double {
        monitor.duration > 0 ? min(max(displayPosition / monitor.duration, 0), 1) : 0
    }

    private var scrubber: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule()
                    .fill(Color.white)
                    .frame(width: max(width * fraction, 0))
                    .shadow(color: monitor.tint.opacity(0.8), radius: scrubFraction == nil ? 0 : 6)
            }
            .frame(height: scrubFraction == nil ? 5 : 8)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard monitor.duration > 0 else { return }
                        scrubFraction = min(max(value.location.x / max(width, 1), 0), 1)
                    }
                    .onEnded { value in
                        guard monitor.duration > 0 else {
                            scrubFraction = nil
                            return
                        }
                        let target = min(max(value.location.x / max(width, 1), 0), 1)
                        monitor.seek(to: target * monitor.duration)
                        scrubFraction = nil
                    }
            )
            .animation(.easeOut(duration: 0.15), value: scrubFraction == nil)
        }
        .frame(height: 16)
    }

    private func control(_ symbol: String, _ size: CGFloat, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .frame(width: 34, height: 30)
                .contentTransition(.symbolEffect(.replace))
                .animation(.snappy(duration: 0.25), value: symbol)
        }
        .buttonStyle(.plain)
    }

    private static func format(_ seconds: Double) -> String {
        let whole = Int(max(seconds, 0))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}

/// More than one app playing: a card each, stacked, the one on the island first.
struct PlayerStack: View {
    @ObservedObject var monitor: NowPlayingMonitor

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 8) {
                ForEach(monitor.players) { player in
                    PlayerCard(player: player, monitor: monitor)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PlayerCard: View {
    let player: NowPlayer
    @ObservedObject var monitor: NowPlayingMonitor
    @State private var hovering = false

    private static let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    var body: some View {
        HStack(spacing: 14) {
            ArtworkView(image: player.artwork, icon: player.icon, size: 58, radius: 12)
                .shadow(color: player.tint.opacity(0.45), radius: 10, y: 4)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if let icon = player.icon {
                        Image(nsImage: icon).resizable().frame(width: 11, height: 11)
                    }
                    Text(player.controllable ? player.name : "\(player.name) · in the background")
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                Text(player.info.title.isEmpty ? player.name : player.info.title)
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1)
                if !player.info.artist.isEmpty {
                    Text(player.info.artist)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if player.controllable {
                HStack(spacing: 14) {
                    control("backward.fill", 13, .previous)
                    control(player.isPlaying ? "pause.fill" : "play.fill", 19, .playPause)
                    control("forward.fill", 13, .next)
                }
            } else {
                // The Mac's media commands cannot reach this app; a click brings it forward instead.
                HStack(spacing: 10) {
                    EqualizerView(color: player.tint)
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(hovering ? 0.9 : 0.5))
                }
                .padding(.trailing, 4)
            }
        }
        .padding(10)
        .background(Self.shape.fill(Color.white.opacity(hovering ? 0.11 : 0.07)))
        .overlay(alignment: .bottom) { progress }
        .clipShape(Self.shape)
        .contentShape(Self.shape)
        .onTapGesture {
            if !player.controllable { monitor.reveal(player) }
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    /// A hairline of progress along the bottom of the card, for a track with a known length.
    @ViewBuilder private var progress: some View {
        if player.info.duration > 0 {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let fraction = NowPlayingMonitor.elapsed(player.info, at: context.date) / player.info.duration
                GeometryReader { proxy in
                    Capsule()
                        .fill(player.tint.opacity(0.9))
                        .frame(width: proxy.size.width * min(max(fraction, 0), 1), height: 2)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .frame(height: 2)
            }
        }
    }

    private func control(_ symbol: String, _ size: CGFloat, _ command: NowPlayingMonitor.Command) -> some View {
        Button {
            monitor.perform(command, on: player)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size))
                .frame(width: 26, height: 26)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
    }
}
