import SwiftUI

/// An activity's icon in the left ear, in its colour, or live bars while it listens.
struct ActivityGlyph: View {
    let activity: LiveActivity

    var body: some View {
        if activity.mic == .listening || activity.mic == .talking {
            ListeningBars(color: activity.tint, talking: activity.mic == .talking, height: 14)
                .shadow(color: activity.tint.opacity(0.6), radius: 4)
        } else {
            Image(systemName: activity.symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(activity.tint)
                .symbolEffect(.pulse, options: .repeating, isActive: activity.endsAt == nil && activity.since == nil)
                .shadow(color: activity.tint.opacity(0.6), radius: 4)
        }
    }
}

/// Bars like a voice, tallest in the middle: lively while you talk, barely stirring while it waits for you.
struct ListeningBars: View {
    let color: Color
    let talking: Bool
    let height: CGFloat

    private static let shape: [CGFloat] = [0.55, 0.8, 1, 0.8, 0.55]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<Self.shape.count, id: \.self) { index in
                    Capsule()
                        .fill(color)
                        .frame(width: 2.5, height: max(2.5, height * Self.shape[index] * level(index, t)))
                }
            }
            .frame(height: height)
        }
        .animation(.easeOut(duration: 0.25), value: talking)
    }

    private func level(_ index: Int, _ t: TimeInterval) -> CGFloat {
        let phase = Double(index) * 1.7
        if talking {
            // Two waves out of step, so it moves like speech rather than a metronome.
            let wave = (sin(t * 9 + phase) + sin(t * 5.3 + phase * 1.9)) / 4 + 0.5
            return 0.3 + 0.7 * CGFloat(wave)
        }
        return 0.25 + 0.12 * CGFloat((sin(t * 2.2 + phase) + 1) / 2)
    }
}

/// The right ear: a countdown, a progress ring, a count up, a short label, or a pulsing dot.
struct ActivityTrailing: View {
    let activity: LiveActivity

    var body: some View {
        Group {
            if let endsAt = activity.endsAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    label(Countdown.format(max(endsAt.timeIntervalSince(context.date), 0)))
                }
            } else if let progress = activity.progress {
                ProgressRing(value: progress, colors: [activity.tint, activity.tint.opacity(0.7)], lineWidth: 2.5)
                    .frame(width: 14, height: 14)
            } else if let since = activity.since {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    label(Countdown.format(max(context.date.timeIntervalSince(since), 0)))
                }
            } else if !activity.trailing.isEmpty {
                label(activity.trailing)
            } else {
                PulsingDot(color: activity.tint)
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(activity.tint)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

struct PulsingDot: View {
    let color: Color
    @State private var on = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .shadow(color: color.opacity(0.8), radius: on ? 5 : 1)
            .opacity(on ? 1 : 0.55)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { on = true }
            }
    }
}

/// Green for the camera, orange for the microphone, purple for the screen, as on iPhone.
struct PrivacyDots: View {
    let indicators: Set<PrivacyIndicator>

    var body: some View {
        VStack(spacing: 3) {
            ForEach(indicators.sorted(), id: \.self) { indicator in
                Circle()
                    .fill(indicator.color)
                    .frame(width: 5, height: 5)
                    .shadow(color: indicator.color.opacity(0.9), radius: 3)
            }
        }
    }
}

/// An activity grown into a card: its icon, title and subtitle on top, then its conversation as it goes, its steps as a
/// checklist that updates in place (done ones ticked, the current one playing), or its progress.
struct ActivityCard: View {
    let activity: LiveActivity
    let topInset: CGFloat

    /// At most four steps: the latest finished ones, the current one and the next.
    static func visibleSteps(_ steps: [LiveActivity.Step]) -> ArraySlice<LiveActivity.Step> {
        guard steps.count > 4 else { return steps[...] }
        let anchor = steps.firstIndex { $0.state == .active || $0.state == .failed }
            ?? steps.lastIndex { $0.state == .done } ?? 0
        let end = min(steps.count, max(anchor + 2, 4))
        return steps[(end - 4)..<end]
    }

    /// The latest three lines of a conversation.
    static func visibleLines(_ lines: [LiveActivity.Line]) -> ArraySlice<LiveActivity.Line> {
        lines.suffix(3)
    }

    /// One line of text, or two for a long one: the card fits about 44 characters a line beside the speaker.
    static func lineHeight(_ line: LiveActivity.Line) -> CGFloat {
        line.text.count > 44 ? 32 : 18
    }

    /// The header alone is as tall as a banner; the conversation, steps or progress go below it, 8 points down.
    static func height(for activity: LiveActivity) -> CGFloat {
        let header = AppState.bannerContentHeight
        if !activity.lines.isEmpty {
            let shown = visibleLines(activity.lines)
            return header + 8 + shown.reduce(0) { $0 + lineHeight($1) } + CGFloat(shown.count - 1) * 6
        }
        if !activity.steps.isEmpty {
            return header + 8 + CGFloat(visibleSteps(activity.steps).count) * 24 - 6
        }
        return activity.progress == nil ? header : header + 8 + 6
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Group {
                    if activity.mic == .listening || activity.mic == .talking {
                        ListeningBars(color: .white, talking: activity.mic == .talking, height: 15)
                    } else {
                        Image(systemName: activity.symbol)
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(activity.tint.gradient))
                .shadow(color: activity.tint.opacity(0.55), radius: 8)
                Text(activity.title)
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1)
                    .layoutPriority(1)
                if !activity.subtitle.isEmpty {
                    Circle().fill(activity.tint).frame(width: 5, height: 5)
                    Text(activity.subtitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(activity.tint)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if activity.endsAt != nil || activity.since != nil || !activity.trailing.isEmpty {
                    ActivityTrailing(activity: activity)
                }
            }
            if !activity.lines.isEmpty {
                dialogue
            } else if !activity.steps.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(Self.visibleSteps(activity.steps).enumerated()), id: \.offset) { _, step in
                        HStack(spacing: 9) {
                            stepIcon(step.state)
                                .frame(width: 16)
                            Text(step.text)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(.white.opacity(step.state == .pending ? 0.45 : 0.92))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .frame(height: 18)
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                    }
                }
                .padding(.leading, 6)
            } else if let progress = activity.progress {
                WidgetBar(value: progress, color: activity.tint, height: 4)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        // Centred top to bottom in the space below the notch, or in the whole card without one.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.top, topInset)
        .foregroundStyle(.white)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: activity.steps)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: activity.lines)
    }

    /// The conversation: each line its speaker, then what they said, the activity's own speaker (the one its title
    /// names) in its colour, and the newest line brightest.
    private var dialogue: some View {
        let shown = Array(Self.visibleLines(activity.lines))
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, line in
                let own = line.speaker.caseInsensitiveCompare(activity.title) == .orderedSame
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(line.speaker)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(own ? activity.tint : .white.opacity(0.55))
                        .lineLimit(1)
                        .frame(width: 46, alignment: .leading)
                    Text(line.text)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white.opacity(index == shown.count - 1 ? 0.95 : 0.62))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(minHeight: 18, alignment: .top)
                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
            }
        }
        .padding(.leading, 6)
    }

    @ViewBuilder private func stepIcon(_ state: LiveActivity.Step.State) -> some View {
        switch state {
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(activity.tint)
        case .active:
            Image(systemName: "play.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(activity.tint)
                .symbolEffect(.pulse, options: .repeating)
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.35))
        case .failed:
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.red)
        }
    }
}
