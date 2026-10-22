import SwiftUI

struct CalendarView: View {
    @ObservedObject var monitor: CalendarMonitor

    var body: some View {
        Group {
            switch monitor.access {
            case .denied:
                message(
                    symbol: "calendar.badge.exclamationmark",
                    title: "Calendar access is off",
                    detail: "Allow Isola in Privacy & Security to see your events.",
                    buttonTitle: "Open Settings",
                    action: monitor.openPrivacySettings
                )
            case .unknown:
                ProgressView().controlSize(.small)
            case .granted:
                if monitor.entries.isEmpty {
                    message(
                        symbol: "checkmark.circle",
                        title: "Nothing coming up",
                        detail: "No events in the next three days.",
                        buttonTitle: nil,
                        action: {}
                    )
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 6) {
                            ForEach(monitor.entries) { entry in
                                row(entry)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { monitor.activate() }
    }

    private func row(_ entry: CalendarEntry) -> some View {
        HStack(spacing: 12) {
            Capsule().fill(entry.color).frame(width: 4, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(timeText(entry))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 8)
            if !entry.isAllDay {
                Text(entry.start, style: .relative)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
    }

    private func timeText(_ entry: CalendarEntry) -> String {
        if entry.isAllDay { return "All day" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = Calendar.current.isDateInToday(entry.start) ? .none : .short
        let end = DateFormatter()
        end.timeStyle = .short
        return "\(formatter.string(from: entry.start)) to \(end.string(from: entry.end))"
    }

    private func message(symbol: String, title: String, detail: String, buttonTitle: String?, action: @escaping () -> Void) -> some View {
        VStack(spacing: 7) {
            Image(systemName: symbol).font(.system(size: 28))
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
            if let buttonTitle {
                Button(action: action) {
                    Text(buttonTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .foregroundStyle(.white.opacity(0.85))
    }
}
