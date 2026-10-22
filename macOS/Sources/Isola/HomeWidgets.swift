import AppKit
import IOKit.pwr_mgt
import SwiftUI
import UniformTypeIdentifiers

/// One widget, on its rounded card.
struct WidgetCard: View {
    let widget: HomeWidget
    @EnvironmentObject var state: AppState

    private static let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Self.shape.fill(Color.white.opacity(0.07)))
            .overlay(Self.shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
            .clipShape(Self.shape)
    }

    @ViewBuilder private var content: some View {
        switch widget {
        case .clock: ClockWidget()
        case .analog: AnalogClockWidget()
        case .world: WorldClockWidget()
        case .media: MediaWidget(monitor: state.nowPlaying)
        case .weather: WeatherWidget(weather: WeatherMonitor.shared)
        case .battery: BatteryWidget(stats: state.system)
        case .system: SystemWidget(stats: state.system)
        case .network: NetworkWidget(stats: state.system)
        case .disk: DiskWidget(stats: state.system)
        case .uptime: UptimeWidget()
        case .calendar: NextEventWidget(monitor: state.calendar)
        case .date: DateWidget()
        case .month: MonthWidget()
        case .progress: ProgressWidget()
        case .timer: TimerWidget(countdown: Countdown.timer)
        case .focus: FocusWidget(session: FocusSession.shared, clock: FocusSession.shared.clock)
        case .stopwatch: StopwatchWidget(watch: Stopwatch.shared)
        case .clipboard: ClipboardWidget(monitor: state.clipboard)
        case .tray: TrayWidget(tray: state.tray)
        case .shortcuts: ShortcutsWidget()
        case .awake: AwakeWidget(awake: KeepAwake.shared)
        case .moon: MoonWidget()
        case .dice: DiceWidget()
        case .counter: CounterWidget()
        case .colors: ColorPickerWidget(picks: ColorPicks.shared)
        }
    }
}

// MARK: Pieces

/// The small caption at the top of each widget.
struct WidgetHeader: View {
    let widget: HomeWidget

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: widget.symbol)
            Text(widget.title.uppercased())
        }
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(.white.opacity(0.5))
        .lineLimit(1)
    }
}

/// A ring that fills clockwise from the top.
struct ProgressRing: View {
    let value: Double
    let colors: [Color]
    var lineWidth: CGFloat = 7

    var body: some View {
        ZStack {
            // Inset by half the line so the whole ring, caps and all, stays inside its frame.
            Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .inset(by: lineWidth / 2)
                .trim(from: 0, to: min(max(value, 0.001), 1))
                .stroke(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: (colors.first ?? .white).opacity(0.5), radius: 6)
        }
    }
}

/// A thin capsule that fills to a fraction.
struct WidgetBar: View {
    let value: Double
    var color: Color = .white
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                Capsule().fill(color).frame(width: proxy.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: height)
    }
}

/// A round button tinted with its colour.
struct WidgetButton: View {
    let symbol: String
    var color: Color = .white
    var size: CGFloat = 30
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.37, weight: .bold))
                .foregroundStyle(color)
                .frame(width: size, height: size)
                .background(Circle().fill(color.opacity(0.18)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: Time

struct ClockWidget: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let date = context.date
            let seconds = Double(Calendar.current.component(.second, from: date))
            VStack(alignment: .leading, spacing: 2) {
                WidgetHeader(widget: .clock)
                Spacer(minLength: 0)
                Text(date.formatted(.dateTime.hour().minute()))
                    .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(date.formatted(.dateTime.weekday(.wide)))
                    .font(.system(size: 11, weight: .semibold))
                Text(date.formatted(.dateTime.day().month(.wide)))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                WidgetBar(value: seconds / 59, color: .orange)
                    .padding(.top, 4)
                    .animation(.linear(duration: 1), value: seconds)
            }
        }
    }
}

struct AnalogClockWidget: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetHeader(widget: .analog)
            Spacer(minLength: 0)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                AnalogFace(date: context.date)
                    .frame(width: 78, height: 78)
                    .frame(maxWidth: .infinity)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct AnalogFace: View {
    let date: Date

    var body: some View {
        let parts = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        let second = Double(parts.second ?? 0)
        let minute = Double(parts.minute ?? 0) + second / 60
        let hour = Double((parts.hour ?? 0) % 12) + minute / 60
        GeometryReader { proxy in
            let radius = min(proxy.size.width, proxy.size.height) / 2
            ZStack {
                Circle().fill(Color.white.opacity(0.08))
                Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                ForEach(0..<12, id: \.self) { i in
                    Capsule()
                        .fill(Color.white.opacity(i % 3 == 0 ? 0.9 : 0.35))
                        .frame(width: i % 3 == 0 ? 2 : 1.2, height: i % 3 == 0 ? 6 : 3.5)
                        .offset(y: -(radius - 6))
                        .rotationEffect(.degrees(Double(i) * 30))
                }
                hand(width: 3, length: radius * 0.5, degrees: hour * 30, color: .white)
                hand(width: 2, length: radius * 0.74, degrees: minute * 6, color: .white)
                hand(width: 1, length: radius * 0.84, degrees: second * 6, color: .orange)
                Circle().fill(Color.orange).frame(width: 5, height: 5)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func hand(width: CGFloat, length: CGFloat, degrees: Double, color: Color) -> some View {
        Capsule()
            .fill(color)
            .frame(width: width, height: length)
            .offset(y: -length / 2)
            .rotationEffect(.degrees(degrees))
    }
}

struct WorldClockWidget: View {
    private struct City: Hashable {
        let name: String
        let zone: String
    }

    private static let cities = [
        City(name: "New York", zone: "America/New_York"),
        City(name: "London", zone: "Europe/London"),
        City(name: "Tokyo", zone: "Asia/Tokyo"),
        City(name: "Sydney", zone: "Australia/Sydney"),
    ]

    /// Three cities, skipping the one you are in.
    private static var picks: [City] {
        Array(cities.filter { $0.zone != TimeZone.current.identifier }.prefix(3))
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            VStack(alignment: .leading, spacing: 5) {
                WidgetHeader(widget: .world)
                Spacer(minLength: 0)
                ForEach(Self.picks, id: \.self) { city in
                    if let zone = TimeZone(identifier: city.zone) {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 2) {
                                Text(city.name)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.55))
                                Spacer(minLength: 0)
                                Text(Self.offset(zone, at: context.date))
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                            Text(Self.time(context.date, in: zone))
                                .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private static func time(_ date: Date, in zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func offset(_ zone: TimeZone, at date: Date) -> String {
        let hours = Double(zone.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date)) / 3600
        if hours == 0 { return "Same" }
        let number = hours == hours.rounded() ? String(Int(hours)) : String(format: "%.1f", hours)
        return (hours > 0 ? "+" : "") + number + "h"
    }
}

struct DateWidget: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 0) {
                WidgetHeader(widget: .date)
                Spacer(minLength: 0)
                Text(context.date.formatted(.dateTime.weekday(.wide)).uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.red)
                    .lineLimit(1)
                Text(context.date.formatted(.dateTime.day()))
                    .font(.system(size: 50, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(context.date.formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
    }
}

struct MonthWidget: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let calendar = Calendar.current
            let today = context.date
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
            let days = calendar.range(of: .day, in: .month, for: today)?.count ?? 30
            let lead = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
            let day = calendar.component(.day, from: today)
            let symbols = calendar.veryShortStandaloneWeekdaySymbols.rotated(by: calendar.firstWeekday - 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(today.formatted(.dateTime.month(.wide)).uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.red)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
                    ForEach(0..<7, id: \.self) { i in
                        Text(symbols[i]).font(.system(size: 7, weight: .semibold)).foregroundStyle(.white.opacity(0.4))
                    }
                    ForEach(0..<(lead + days), id: \.self) { i in
                        let n = i - lead + 1
                        Text(n > 0 ? "\(n)" : "")
                            .font(.system(size: 8, weight: n == day ? .bold : .regular).monospacedDigit())
                            .foregroundStyle(n == day ? Color.white : Color.white.opacity(0.75))
                            .frame(width: 13, height: 13)
                            .background(Circle().fill(n == day ? Color.red : Color.clear))
                    }
                }
            }
        }
    }
}

struct ProgressWidget: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 5) {
                WidgetHeader(widget: .progress)
                Spacer(minLength: 0)
                row("Day", .day, context.date, .orange)
                row("Week", .weekOfYear, context.date, .yellow)
                row("Month", .month, context.date, .green)
                row("Year", .year, context.date, .purple)
                Spacer(minLength: 0)
            }
        }
    }

    private func row(_ title: String, _ unit: Calendar.Component, _ date: Date, _ color: Color) -> some View {
        let fraction = Self.fraction(of: unit, at: date)
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                Spacer(minLength: 0)
                Text("\(Int(fraction * 100))%").font(.system(size: 9, weight: .bold).monospacedDigit())
            }
            WidgetBar(value: fraction, color: color, height: 4)
        }
    }

    static func fraction(of unit: Calendar.Component, at date: Date) -> Double {
        guard let interval = Calendar.current.dateInterval(of: unit, for: date), interval.duration > 0 else { return 0 }
        return date.timeIntervalSince(interval.start) / interval.duration
    }
}

struct UptimeWidget: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let boot = Self.bootDate
            VStack(alignment: .leading, spacing: 3) {
                WidgetHeader(widget: .uptime)
                Spacer(minLength: 0)
                Image(systemName: "power")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.green)
                Text(Self.format(context.date.timeIntervalSince(boot)))
                    .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("since \(boot.formatted(.dateTime.weekday().hour().minute()))")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
        }
    }

    /// When the Mac started, from the kernel, so time spent asleep counts too.
    static var bootDate: Date {
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        var time = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctl(&mib, 2, &time, &size, nil, 0) == 0 else {
            return Date().addingTimeInterval(-ProcessInfo.processInfo.systemUptime)
        }
        return Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_usec) / 1_000_000)
    }

    static func format(_ seconds: TimeInterval) -> String {
        let minutes = max(Int(seconds / 60), 0)
        let days = minutes / 1440, hours = minutes / 60 % 24, rest = minutes % 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(rest)m" }
        return "\(rest)m"
    }
}

// MARK: Media and system

struct MediaWidget: View {
    @ObservedObject var monitor: NowPlayingMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(widget: .media)
            if monitor.hasTrack {
                HStack(spacing: 10) {
                    ArtworkView(image: monitor.artwork, icon: monitor.sourceIcon, size: 58, radius: 12)
                        .shadow(color: monitor.tint.opacity(0.5), radius: 10, y: 3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(monitor.title).font(.system(size: 13, weight: .bold)).lineLimit(1)
                        Text(monitor.artist).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                        Text(monitor.sourceName).font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.4)).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                WidgetBar(value: monitor.duration > 0 ? monitor.position / monitor.duration : 0, color: monitor.tint)
                HStack(spacing: 26) {
                    button("backward.fill", 13, monitor.previous)
                    button(monitor.isPlaying ? "pause.fill" : "play.fill", 19, monitor.togglePlayPause)
                    button("forward.fill", 13, monitor.next)
                }
                .frame(maxWidth: .infinity)
                .disabled(monitor.isBackground)
                .opacity(monitor.isBackground ? 0.35 : 1)
            } else {
                Spacer(minLength: 0)
                Text("Nothing playing").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                Text("Play music or a video in any app.").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                Spacer(minLength: 0)
            }
        }
    }

    private func button(_ symbol: String, _ size: CGFloat, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size)).frame(width: 26, height: 24)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
    }
}

struct BatteryWidget: View {
    @ObservedObject var stats: SystemStats

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetHeader(widget: .battery)
            Spacer(minLength: 0)
            if let level = stats.battery {
                let low = level <= 20 && !stats.isCharging
                ZStack {
                    ProgressRing(value: Double(level) / 100, colors: low ? [.red, .orange] : [.green, .mint])
                        .animation(.easeOut(duration: 0.6), value: level)
                    VStack(spacing: 0) {
                        if stats.isCharging {
                            Image(systemName: "bolt.fill").font(.system(size: 10)).foregroundStyle(.green)
                        }
                        Text("\(level)%").font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                    }
                }
                .frame(width: 70, height: 70)
                .frame(maxWidth: .infinity)
                Text(stats.isCharging ? "Charging" : "On battery")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity)
            } else {
                Image(systemName: "powerplug.fill").font(.system(size: 26)).frame(maxWidth: .infinity)
                Text("On power").font(.system(size: 11, weight: .semibold)).frame(maxWidth: .infinity)
                Text("No battery").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).frame(maxWidth: .infinity)
            }
            Spacer(minLength: 0)
        }
    }
}

struct SystemWidget: View {
    @ObservedObject var stats: SystemStats

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(widget: .system)
            metric("CPU", stats.cpu, stats.cpuHistory, .mint)
            metric("Memory", stats.memory, stats.memoryHistory, .orange)
        }
    }

    private func metric(_ title: String, _ value: Double, _ history: [Double], _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                Spacer(minLength: 0)
                Text("\(Int(value * 100))%").font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
            }
            Sparkline(values: history, color: color).frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
    }
}

/// A small line graph, filled underneath, scaled 0 to 1.
struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let points = values.isEmpty ? [0, 0] : (values.count == 1 ? values + values : values)
            let step = proxy.size.width / CGFloat(max(points.count - 1, 1))
            let y = { (v: Double) in proxy.size.height * (1 - CGFloat(min(max(v, 0), 1))) }
            let line = Path { path in
                for (i, v) in points.enumerated() {
                    let p = CGPoint(x: CGFloat(i) * step, y: y(v))
                    i == 0 ? path.move(to: p) : path.addLine(to: p)
                }
            }
            ZStack {
                Path { path in
                    path.addPath(line)
                    path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height))
                    path.addLine(to: CGPoint(x: 0, y: proxy.size.height))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [color.opacity(0.35), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                line.stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
        .animation(.easeOut(duration: 0.4), value: values)
    }
}

struct NetworkWidget: View {
    @ObservedObject var stats: SystemStats

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetHeader(widget: .network)
            Spacer(minLength: 0)
            rate("arrow.down", stats.netDown, .blue)
            rate("arrow.up", stats.netUp, .green)
            let peak = max(stats.netHistory.max() ?? 0, 1)
            Sparkline(values: stats.netHistory.map { $0 / peak }, color: .blue)
                .frame(height: 30)
                .padding(.top, 4)
            Spacer(minLength: 0)
        }
    }

    private func rate(_ symbol: String, _ value: Double, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(color)
            Text(Self.format(value))
                .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    static func format(_ bytes: Double) -> String {
        bytes >= 1_000_000 ? String(format: "%.1f MB/s", bytes / 1_000_000) : String(format: "%.0f KB/s", bytes / 1_000)
    }
}

struct DiskWidget: View {
    @ObservedObject var stats: SystemStats

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetHeader(widget: .disk)
            Spacer(minLength: 0)
            ZStack {
                ProgressRing(value: stats.disk, colors: [.cyan, .indigo])
                Text("\(Int(stats.disk * 100))%").font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
            }
            .frame(width: 70, height: 70)
            .frame(maxWidth: .infinity)
            Text(stats.diskText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
    }
}

// MARK: Weather

/// Today's weather where you are: a rough location from your network address (so no location permission), then the
/// forecast from Open-Meteo. Fetched when the widget shows, at most every 15 minutes.
final class WeatherMonitor: ObservableObject {
    struct Report {
        let temperature: Double
        let high: Double
        let low: Double
        let code: Int
        let isDay: Bool
        let place: String
    }

    static let shared = WeatherMonitor()

    @Published private(set) var report: Report?
    @Published private(set) var failed = false
    private var fetchedAt: Date?
    private var loading = false

    func refresh(force: Bool = false) {
        if !force, let fetchedAt, Date().timeIntervalSince(fetchedAt) < 15 * 60 { return }
        guard !loading else { return }
        loading = true
        failed = false
        fetchJSON("https://get.geojs.io/v1/ip/geo.json") { [weak self] geo in
            guard let self else { return }
            guard let geo, let latitude = Self.number(geo["latitude"]), let longitude = Self.number(geo["longitude"]) else {
                return self.finish(nil)
            }
            let place = geo["city"] as? String ?? ""
            let unit = Locale.current.measurementSystem == .us ? "fahrenheit" : "celsius"
            let address = "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)"
                + "&current=temperature_2m,weather_code,is_day&daily=temperature_2m_max,temperature_2m_min"
                + "&timezone=auto&forecast_days=1&temperature_unit=\(unit)"
            self.fetchJSON(address) { json in
                guard let current = json?["current"] as? [String: Any],
                      let temperature = Self.number(current["temperature_2m"]) else { return self.finish(nil) }
                let daily = json?["daily"] as? [String: Any]
                let high = Self.number((daily?["temperature_2m_max"] as? [Any])?.first) ?? temperature
                let low = Self.number((daily?["temperature_2m_min"] as? [Any])?.first) ?? temperature
                let code = Int(Self.number(current["weather_code"]) ?? 3)
                let isDay = (Self.number(current["is_day"]) ?? 1) == 1
                self.finish(Report(temperature: temperature, high: high, low: low, code: code, isDay: isDay, place: place))
            }
        }
    }

    private func finish(_ report: Report?) {
        DispatchQueue.main.async {
            self.loading = false
            if let report {
                self.report = report
                self.fetchedAt = Date()
            } else if self.report == nil {
                self.failed = true
            }
        }
    }

    private func fetchJSON(_ address: String, done: @escaping ([String: Any]?) -> Void) {
        guard let url = URL(string: address) else { return done(nil) }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            done(data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        }.resume()
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }

    /// The symbol and words for a WMO weather code.
    static func describe(_ code: Int, day: Bool) -> (symbol: String, text: String) {
        switch code {
        case 0: return (day ? "sun.max.fill" : "moon.stars.fill", "Clear")
        case 1, 2: return (day ? "cloud.sun.fill" : "cloud.moon.fill", "Partly cloudy")
        case 3: return ("cloud.fill", "Cloudy")
        case 45, 48: return ("cloud.fog.fill", "Fog")
        case 51...57: return ("cloud.drizzle.fill", "Drizzle")
        case 61...67: return ("cloud.rain.fill", "Rain")
        case 71...77, 85, 86: return ("cloud.snow.fill", "Snow")
        case 80...82: return ("cloud.heavyrain.fill", "Showers")
        case 95...99: return ("cloud.bolt.rain.fill", "Thunderstorm")
        default: return ("cloud.fill", "Cloudy")
        }
    }
}

struct WeatherWidget: View {
    @ObservedObject var weather: WeatherMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            WidgetHeader(widget: .weather)
            Spacer(minLength: 0)
            if let report = weather.report {
                let look = WeatherMonitor.describe(report.code, day: report.isDay)
                Image(systemName: look.symbol)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 24))
                Text("\(Int(report.temperature.rounded()))°")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text(look.text).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                Text("H \(Int(report.high.rounded()))°  L \(Int(report.low.rounded()))°")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.55))
                if !report.place.isEmpty {
                    Text(report.place).font(.system(size: 9)).foregroundStyle(.white.opacity(0.4)).lineLimit(1)
                }
            } else if weather.failed {
                Image(systemName: "icloud.slash").font(.system(size: 22)).foregroundStyle(.white.opacity(0.5))
                Text("Weather unavailable").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                Button("Try again") { weather.refresh(force: true) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.blue)
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity)
            }
            Spacer(minLength: 0)
        }
        .onAppear { weather.refresh() }
    }
}

// MARK: Calendar

struct NextEventWidget: View {
    @ObservedObject var monitor: CalendarMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(widget: .calendar)
            Spacer(minLength: 0)
            switch monitor.access {
            case .denied:
                Text("Calendar access is off").font(.system(size: 12, weight: .semibold))
                Button("Open Settings") { monitor.openPrivacySettings() }.controlSize(.small)
            case .unknown:
                ProgressView().controlSize(.small)
            case .granted:
                if let event = monitor.entries.first(where: { $0.end > Date() }) {
                    HStack(alignment: .top, spacing: 10) {
                        Capsule().fill(event.color).frame(width: 4, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title).font(.system(size: 14, weight: .bold)).lineLimit(2)
                            Text(event.isAllDay ? "All day" : event.start.formatted(.dateTime.weekday().hour().minute()))
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.6))
                            if !event.isAllDay {
                                TimelineView(.periodic(from: .now, by: 30)) { _ in
                                    Text(event.start > Date() ? "in \(Self.relative(event.start))" : "now")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(event.color)
                                }
                            }
                        }
                    }
                } else {
                    Text("Nothing coming up").font(.system(size: 13, weight: .semibold))
                    Text("No events in the next three days.").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                }
            }
            Spacer(minLength: 0)
        }
    }

    static func relative(_ date: Date) -> String {
        let minutes = max(Int(date.timeIntervalSinceNow / 60), 0)
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        if hours < 24 { return minutes % 60 == 0 ? "\(hours) hr" : "\(hours) hr \(minutes % 60) min" }
        return "\(hours / 24) d"
    }
}

// MARK: Timers

/// Plays an alarm over and over until it is answered, for a minute at most.
enum Ringer {
    private static var sound: NSSound?

    static func start(_ name: String = "Glass") {
        stop()
        guard UserDefaults.standard.bool(forKey: Prefs.liveTimers) else {
            NSSound(named: NSSound.Name(name))?.play()
            return
        }
        let ringing = NSSound(named: NSSound.Name(name))
        ringing?.loops = true
        ringing?.play()
        sound = ringing
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            if sound === ringing { stop() }
        }
    }

    static func stop() {
        sound?.stop()
        sound = nil
    }
}

/// A countdown that keeps going while the island is closed, sits in the ears while it runs, and rings when it is done.
final class Countdown: ObservableObject {
    static let timer: Countdown = {
        let countdown = Countdown()
        countdown.look = (id: "isola.timer", symbol: "timer", tint: .orange, title: "Timer")
        countdown.onFinish = { [weak countdown] in
            guard let countdown else { return }
            let total = countdown.total
            let minutes = Int(total / 60)
            Ringer.start()
            AppState.shared.showBanner(IslandBanner(
                symbol: "timer", tint: .orange, title: "Timer done",
                subtitle: "\(minutes) minute\(minutes == 1 ? "" : "s") are up",
                action: BannerAction(title: "Stop", symbol: "stop.fill") {},
                secondAction: BannerAction(title: "Repeat", symbol: "arrow.clockwise") { countdown.start(total) },
                ringing: true,
                onDismiss: { Ringer.stop() }
            ), for: 60)
        }
        return countdown
    }()

    /// How it shows in the ears while it runs. Nil keeps it out of the island.
    var look: (id: String, symbol: String, tint: Color, title: String)? {
        didSet { syncActivity() }
    }

    @Published private(set) var endsAt: Date?
    @Published private(set) var pausedRemaining: TimeInterval?
    @Published private(set) var total: TimeInterval = 0
    var onFinish: (() -> Void)?
    private var work: DispatchWorkItem?

    var isRunning: Bool { endsAt != nil }
    var isActive: Bool { endsAt != nil || pausedRemaining != nil }

    func remaining(at date: Date) -> TimeInterval {
        if let endsAt { return max(endsAt.timeIntervalSince(date), 0) }
        return pausedRemaining ?? total
    }

    func start(_ seconds: TimeInterval) {
        total = seconds
        pausedRemaining = nil
        schedule(seconds)
    }

    func pause() {
        guard let endsAt else { return }
        pausedRemaining = max(endsAt.timeIntervalSinceNow, 0)
        self.endsAt = nil
        work?.cancel()
        syncActivity()
    }

    func resume() {
        guard let left = pausedRemaining else { return }
        pausedRemaining = nil
        schedule(left)
    }

    func cancel() {
        work?.cancel()
        endsAt = nil
        pausedRemaining = nil
        syncActivity()
    }

    private func schedule(_ seconds: TimeInterval) {
        work?.cancel()
        endsAt = Date().addingTimeInterval(seconds)
        let item = DispatchWorkItem { [weak self] in self?.finish() }
        work = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
        syncActivity()
    }

    private func finish() {
        endsAt = nil
        pausedRemaining = nil
        syncActivity()
        onFinish?()
    }

    /// Running, it counts down in the ears; paused, it shows the time left; stopped, it leaves.
    private func syncActivity() {
        guard let look else { return }
        if endsAt != nil || pausedRemaining != nil {
            AppState.shared.setActivity(LiveActivity(
                id: look.id, symbol: look.symbol, tint: look.tint, title: look.title,
                trailing: endsAt == nil ? Self.format(remaining(at: Date())) : "",
                endsAt: endsAt, priority: 1
            ))
        } else {
            AppState.shared.endActivity(look.id)
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// A countdown's ring with the time left in the middle.
struct CountdownFace: View {
    @ObservedObject var countdown: Countdown
    let colors: [Color]
    /// What it shows before it starts.
    var idle: TimeInterval = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.25, paused: !countdown.isRunning)) { context in
            let active = countdown.isActive
            let remaining = active ? countdown.remaining(at: context.date) : idle
            ZStack {
                ProgressRing(value: active && countdown.total > 0 ? remaining / countdown.total : 1, colors: colors, lineWidth: 6)
                Text(Countdown.format(remaining))
                    .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }
}

struct TimerWidget: View {
    @ObservedObject var countdown: Countdown
    private static let presets = [1, 5, 10, 25]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(widget: .timer)
            Spacer(minLength: 0)
            if countdown.isActive {
                CountdownFace(countdown: countdown, colors: [.orange, .yellow])
                    .frame(width: 64, height: 64)
                    .frame(maxWidth: .infinity)
                HStack(spacing: 8) {
                    WidgetButton(symbol: countdown.isRunning ? "pause.fill" : "play.fill", color: .orange) {
                        countdown.isRunning ? countdown.pause() : countdown.resume()
                    }
                    WidgetButton(symbol: "xmark") { countdown.cancel() }
                }
                .frame(maxWidth: .infinity)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                    ForEach(Self.presets, id: \.self) { minutes in
                        Button {
                            countdown.start(TimeInterval(minutes * 60))
                        } label: {
                            Text("\(minutes)m")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(.orange)
                                .frame(maxWidth: .infinity)
                                .frame(height: 30)
                                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.orange.opacity(0.18)))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Pick a time").font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.45)).frame(maxWidth: .infinity)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Pomodoro: 25 minutes of focus, then a 5 minute break (15 after every fourth), each announced in the island.
final class FocusSession: ObservableObject {
    enum Phase { case focus, rest }

    static let shared = FocusSession()
    static let focusLength: TimeInterval = 25 * 60
    static let restLength: TimeInterval = 5 * 60

    @Published private(set) var phase: Phase = .focus
    @Published private(set) var completed = 0
    let clock = Countdown()

    private init() {
        clock.onFinish = { [weak self] in self?.advance() }
        updateLook()
    }

    /// A long break after every fourth session.
    private var restLength: TimeInterval { completed > 0 && completed % 4 == 0 ? 15 * 60 : Self.restLength }

    func toggle() {
        if clock.isRunning {
            clock.pause()
        } else if clock.isActive {
            clock.resume()
        } else {
            clock.start(phase == .focus ? Self.focusLength : restLength)
        }
    }

    func reset() {
        clock.cancel()
        phase = .focus
        completed = 0
        updateLook()
    }

    private func updateLook() {
        clock.look = phase == .focus
            ? (id: "isola.focus", symbol: "brain.head.profile", tint: .red, title: "Focus")
            : (id: "isola.focus", symbol: "cup.and.saucer.fill", tint: .green, title: "Break")
    }

    /// Each session ends by ringing in the island, and the next one starts when you say so.
    private func advance() {
        Ringer.start()
        if phase == .focus {
            completed += 1
            phase = .rest
            updateLook()
            let length = restLength
            AppState.shared.showBanner(IslandBanner(
                symbol: "cup.and.saucer.fill", tint: .green, title: "Time for a break",
                subtitle: length > Self.restLength ? "15 minutes. You've earned it." : "5 minutes",
                action: BannerAction(title: "Start break", symbol: "play.fill") { [weak self] in self?.clock.start(length) },
                secondAction: BannerAction(title: "Skip", symbol: "forward.fill") { [weak self] in self?.skipBreak() },
                ringing: true,
                onDismiss: { Ringer.stop() }
            ), for: 60)
        } else {
            phase = .focus
            updateLook()
            AppState.shared.showBanner(IslandBanner(
                symbol: "brain.head.profile", tint: .red, title: "Break's over",
                subtitle: "Ready for the next session?",
                action: BannerAction(title: "Start focus", symbol: "play.fill") { [weak self] in
                    self?.clock.start(Self.focusLength)
                },
                secondAction: BannerAction(title: "Later", symbol: "clock") {},
                ringing: true,
                onDismiss: { Ringer.stop() }
            ), for: 60)
        }
    }

    func skipBreak() {
        clock.cancel()
        phase = .focus
        updateLook()
    }
}

struct FocusWidget: View {
    @ObservedObject var session: FocusSession
    @ObservedObject var clock: Countdown

    var body: some View {
        let focus = session.phase == .focus
        let colors: [Color] = focus ? [.red, .orange] : [.green, .mint]
        VStack(alignment: .leading, spacing: 5) {
            WidgetHeader(widget: .focus)
            Spacer(minLength: 0)
            CountdownFace(countdown: clock, colors: colors, idle: focus ? FocusSession.focusLength : FocusSession.restLength)
                .frame(width: 56, height: 56)
                .frame(maxWidth: .infinity)
            HStack(spacing: 3) {
                Text(focus ? "Focus" : "Break").font(.system(size: 10, weight: .bold)).foregroundStyle(colors[0])
                Spacer(minLength: 0)
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(i < session.completed % 4 ? colors[0] : Color.white.opacity(0.2))
                        .frame(width: 5, height: 5)
                }
            }
            HStack(spacing: 8) {
                WidgetButton(symbol: clock.isRunning ? "pause.fill" : "play.fill", color: colors[0], size: 28) { session.toggle() }
                WidgetButton(symbol: "arrow.counterclockwise", size: 28) { session.reset() }
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
    }
}

/// A stopwatch that keeps running while the island is closed.
final class Stopwatch: ObservableObject {
    static let shared = Stopwatch()
    @Published private(set) var startedAt: Date?
    @Published private(set) var stored: TimeInterval = 0

    var running: Bool { startedAt != nil }

    func elapsed(at date: Date) -> TimeInterval {
        stored + (startedAt.map { date.timeIntervalSince($0) } ?? 0)
    }

    func toggle() {
        if let startedAt {
            stored += Date().timeIntervalSince(startedAt)
            self.startedAt = nil
        } else {
            startedAt = Date()
        }
        syncActivity()
    }

    func reset() {
        startedAt = running ? Date() : nil
        stored = 0
        syncActivity()
    }

    /// Running, it counts up in the ears.
    private func syncActivity() {
        if let startedAt {
            AppState.shared.setActivity(LiveActivity(
                id: "isola.stopwatch", symbol: "stopwatch.fill", tint: .yellow, title: "Stopwatch",
                since: startedAt.addingTimeInterval(-stored), priority: 1
            ))
        } else {
            AppState.shared.endActivity("isola.stopwatch")
        }
    }
}

struct StopwatchWidget: View {
    @ObservedObject var watch: Stopwatch

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(widget: .stopwatch)
            Spacer(minLength: 0)
            TimelineView(.animation(minimumInterval: 0.1, paused: !watch.running)) { context in
                Text(Self.format(watch.elapsed(at: context.date)))
                    .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(watch.running ? Color.orange : Color.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                WidgetButton(symbol: watch.running ? "pause.fill" : "play.fill", color: watch.running ? .orange : .green) { watch.toggle() }
                WidgetButton(symbol: "arrow.counterclockwise") { watch.reset() }
                    .opacity(watch.elapsed(at: Date()) > 0 ? 1 : 0.4)
            }
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let tenths = Int(seconds * 10)
        let s = tenths / 10
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d.%d", s / 60, s % 60, tenths % 10)
    }
}

// MARK: Files and clipboard

struct ClipboardWidget: View {
    @ObservedObject var monitor: ClipboardMonitor
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(widget: .clipboard)
            if let entry = monitor.entries.first {
                Button {
                    monitor.copy(entry)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                } label: {
                    preview(entry)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .overlay {
                            if copied {
                                Label("Copied", systemImage: "checkmark.circle.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.green)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(Color.black.opacity(0.6))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .animation(.easeOut(duration: 0.15), value: copied)
            } else {
                Spacer(minLength: 0)
                Text("Nothing copied yet").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder private func preview(_ entry: ClipboardEntry) -> some View {
        switch entry.kind {
        case .image:
            if let image = monitor.image(entry) {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Image(systemName: "photo").font(.system(size: 22)).foregroundStyle(.white.opacity(0.4))
            }
        case .color:
            let rgb = ClipboardMonitor.rgb(entry.text)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(rgb.map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? Color.gray)
                .overlay(Text(entry.text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .shadow(radius: 2))
        default:
            Text(entry.text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(6)
        }
    }
}

struct TrayWidget: View {
    @ObservedObject var tray: FileTray
    @EnvironmentObject var state: AppState
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(widget: .tray)
            Spacer(minLength: 0)
            if tray.items.isEmpty {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 24))
                    .foregroundStyle(.white.opacity(targeted ? 1 : 0.6))
                    .frame(maxWidth: .infinity)
                Text("Drop files here")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: -14) {
                    ForEach(tray.items.suffix(3)) { item in
                        Image(nsImage: item.icon).resizable().frame(width: 38, height: 38).shadow(radius: 3)
                    }
                }
                .frame(maxWidth: .infinity)
                Text("\(tray.items.count) file\(tray.items.count == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .bold))
                    .frame(maxWidth: .infinity)
                Button("Open tray") {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.76)) { state.tab = .tray }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(maxWidth: .infinity)
            }
            Spacer(minLength: 0)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.blue.opacity(targeted ? 0.8 : 0), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .padding(-6)
        )
        .onDrop(of: [.fileURL], isTargeted: $targeted) { tray.handleDrop($0) }
    }
}

// MARK: Shortcuts and toggles

struct ShortcutsWidget: View {
    private struct Shortcut: Identifiable {
        let id: String
        let symbol: String
        let color: Color
        let run: () -> Void
    }

    private static let shortcuts = [
        Shortcut(id: "Finder", symbol: "folder.fill", color: .blue) {
            NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser)
        },
        Shortcut(id: "Screenshot", symbol: "camera.viewfinder", color: .gray) {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app"))
        },
        Shortcut(id: "Activity", symbol: "waveform.path.ecg", color: .green) {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
        },
        Shortcut(id: "Sleep", symbol: "moon.zzz.fill", color: .indigo) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            process.arguments = ["displaysleepnow"]
            try? process.run()
        },
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(widget: .shortcuts)
            Spacer(minLength: 0)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)], spacing: 8) {
                ForEach(Self.shortcuts) { shortcut in
                    Button(action: shortcut.run) {
                        VStack(spacing: 3) {
                            Image(systemName: shortcut.symbol)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(shortcut.color.opacity(0.55)))
                            Text(shortcut.id)
                                .font(.system(size: 8.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Keeps the display from sleeping while it is on.
final class KeepAwake: ObservableObject {
    static let shared = KeepAwake()
    @Published private(set) var since: Date?
    private var assertion: IOPMAssertionID = 0

    var isOn: Bool { since != nil }

    func toggle() {
        if isOn {
            IOPMAssertionRelease(assertion)
            since = nil
        } else if IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                              IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                              "Keep Awake in Isola" as CFString, &assertion) == kIOReturnSuccess {
            since = Date()
        }
    }
}

struct AwakeWidget: View {
    @ObservedObject var awake: KeepAwake

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            WidgetHeader(widget: .awake)
            Spacer(minLength: 0)
            Button { awake.toggle() } label: {
                Image(systemName: awake.isOn ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(awake.isOn ? Color.black : Color.white.opacity(0.8))
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(awake.isOn ? Color.yellow : Color.white.opacity(0.1)))
                    .shadow(color: awake.isOn ? Color.yellow.opacity(0.5) : Color.clear, radius: 10)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            Text(awake.isOn ? "Staying awake" : "Sleeps as usual")
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            if let since = awake.since {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text("for \(UptimeWidget.format(context.date.timeIntervalSince(since)))")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                }
            }
            Spacer(minLength: 0)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: awake.isOn)
    }
}

// MARK: Fun

/// The moon's phase, worked out from a known new moon and the length of a lunar month.
struct Moon {
    static let cycle = 29.530588853
    /// Days since the last new moon.
    let age: Double

    init(date: Date) {
        let reference = Date(timeIntervalSince1970: 947_182_440) // 6 January 2000, 18:14 UTC: a new moon
        let days = date.timeIntervalSince(reference) / 86_400
        age = (days.truncatingRemainder(dividingBy: Self.cycle) + Self.cycle).truncatingRemainder(dividingBy: Self.cycle)
    }

    var illumination: Double { (1 - cos(2 * .pi * age / Self.cycle)) / 2 }
    private var index: Int { Int((age / Self.cycle * 8).rounded()) % 8 }

    var name: String {
        ["New Moon", "Waxing Crescent", "First Quarter", "Waxing Gibbous",
         "Full Moon", "Waning Gibbous", "Last Quarter", "Waning Crescent"][index]
    }

    var symbol: String {
        ["moonphase.new.moon", "moonphase.waxing.crescent", "moonphase.first.quarter", "moonphase.waxing.gibbous",
         "moonphase.full.moon", "moonphase.waning.gibbous", "moonphase.last.quarter", "moonphase.waning.crescent"][index]
    }

    var nextFull: String {
        var days = Self.cycle / 2 - age
        if days < 0 { days += Self.cycle }
        let whole = Int(days.rounded())
        return whole == 0 ? "Full moon tonight" : "Full in \(whole) day\(whole == 1 ? "" : "s")"
    }
}

struct MoonWidget: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 600)) { context in
            let moon = Moon(date: context.date)
            VStack(alignment: .leading, spacing: 2) {
                WidgetHeader(widget: .moon)
                Spacer(minLength: 0)
                Image(systemName: moon.symbol)
                    .font(.system(size: 40))
                    .foregroundStyle(Color(white: 0.92))
                    .shadow(color: .white.opacity(0.35), radius: 8)
                    .frame(maxWidth: .infinity)
                Text(moon.name)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                Text("\(Int((moon.illumination * 100).rounded()))% lit")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity)
                Text(moon.nextFull)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
        }
    }
}

struct DiceWidget: View {
    @State private var value = Int.random(in: 1...6)
    @State private var spin = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(widget: .dice)
            Spacer(minLength: 0)
            Button {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                    spin += 360
                    value = Int.random(in: 1...6)
                }
            } label: {
                Image(systemName: "die.face.\(value).fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(spin))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            Text("Click to roll").font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.45)).frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
    }
}

struct CounterWidget: View {
    @AppStorage(Prefs.homeCounter) private var count = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(widget: .counter)
            Spacer(minLength: 0)
            Text("\(count)")
                .font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText(value: Double(count)))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                WidgetButton(symbol: "minus", color: .pink) { withAnimation { count -= 1 } }
                WidgetButton(symbol: "plus", color: .pink) { withAnimation { count += 1 } }
            }
            .frame(maxWidth: .infinity)
            Button("Reset") { withAnimation { count = 0 } }
                .buttonStyle(.plain)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.white.opacity(count == 0 ? 0.25 : 0.55))
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
    }
}

/// Colours picked from anywhere on screen, newest first, kept between launches.
final class ColorPicks: ObservableObject {
    static let shared = ColorPicks()
    private static let key = "home.colors"
    @Published private(set) var colors: [String] = UserDefaults.standard.stringArray(forKey: ColorPicks.key) ?? []

    /// The system eyedropper: click any pixel on any screen, and its hex code is copied.
    func pick() {
        NSColorSampler().show { [weak self] picked in
            guard let self, let color = picked?.usingColorSpace(.sRGB) else { return }
            let hex = String(format: "#%02X%02X%02X", Int(round(color.redComponent * 255)),
                             Int(round(color.greenComponent * 255)), Int(round(color.blueComponent * 255)))
            self.copy(hex)
            self.colors = Array(([hex] + self.colors.filter { $0 != hex }).prefix(5))
            UserDefaults.standard.set(self.colors, forKey: Self.key)
        }
    }

    func copy(_ hex: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(hex, forType: .string)
    }

    static func color(_ hex: String) -> Color {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
        return Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                     blue: Double(value & 0xFF) / 255)
    }
}

struct ColorPickerWidget: View {
    @ObservedObject var picks: ColorPicks
    @State private var copied: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(widget: .colors)
            Spacer(minLength: 0)
            if let latest = picks.colors.first {
                Button { copy(latest) } label: {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(ColorPicks.color(latest))
                        .frame(height: 38)
                        .overlay(
                            Text(copied == latest ? "Copied" : latest)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                                .shadow(radius: 2)
                        )
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.2)))
                }
                .buttonStyle(.plain)
                HStack(spacing: 5) {
                    ForEach(Array(picks.colors.dropFirst()), id: \.self) { hex in
                        Button { copy(hex) } label: {
                            Circle().fill(ColorPicks.color(hex)).frame(width: 14, height: 14)
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.25)))
                        }
                        .buttonStyle(.plain)
                        .help(hex)
                    }
                }
            } else {
                Text("Pick any colour on screen and its hex code is copied.")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button { picks.pick() } label: {
                Label("Pick", systemImage: "eyedropper")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white))
            }
            .buttonStyle(.plain)
        }
    }

    private func copy(_ hex: String) {
        picks.copy(hex)
        copied = hex
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { if copied == hex { copied = nil } }
    }
}

private extension Array {
    func rotated(by amount: Int) -> [Element] {
        guard !isEmpty else { return self }
        let n = ((amount % count) + count) % count
        return Array(self[n...] + self[..<n])
    }
}
