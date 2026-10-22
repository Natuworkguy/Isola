import SwiftUI

struct SystemView: View {
    @ObservedObject var stats: SystemStats

    var body: some View {
        HStack(spacing: 26) {
            gauge("CPU", value: stats.cpu, detail: "\(Int(stats.cpu * 100))%", colors: [.mint, .green])
            gauge("Memory", value: stats.memory, detail: stats.memoryText, colors: [.yellow, .orange])
            gauge("Disk", value: stats.disk, detail: stats.diskText, colors: [.cyan, .blue])
            if let level = stats.battery {
                gauge(
                    stats.isCharging ? "Charging" : "Battery",
                    value: Double(level) / 100,
                    detail: "\(level)%",
                    colors: level <= 20 && !stats.isCharging ? [.red, .orange] : [.green, .mint]
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { stats.start() }
        .onDisappear { stats.stop() }
    }

    private func gauge(_ title: String, value: Double, detail: String, colors: [Color]) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: max(min(value, 1), 0.001))
                    .stroke(
                        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: colors[0].opacity(0.5), radius: 6)
                    .animation(.easeOut(duration: 0.6), value: value)
                Text("\(Int(value * 100))")
                    .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
            }
            .frame(width: 82, height: 82)

            VStack(spacing: 1) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
        }
        .frame(minWidth: 90)
    }
}
