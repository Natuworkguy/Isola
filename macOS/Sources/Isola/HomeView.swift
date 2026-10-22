import AppKit
import SwiftUI

/// The widgets the Home tab can show. The pencil on the Home tab chooses which, and arranges them.
enum HomeWidget: String, CaseIterable, Identifiable {
    case clock, analog, world, media, weather, battery, system, network, disk, uptime
    case calendar, date, month, progress, timer, focus, stopwatch, clipboard, tray, shortcuts
    case awake, moon, dice, counter, colors

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clock: return "Clock"
        case .analog: return "Analog Clock"
        case .world: return "World Clock"
        case .media: return "Now Playing"
        case .weather: return "Weather"
        case .battery: return "Battery"
        case .system: return "System"
        case .network: return "Network"
        case .disk: return "Storage"
        case .uptime: return "Uptime"
        case .calendar: return "Next Event"
        case .date: return "Today"
        case .month: return "Month"
        case .progress: return "Progress"
        case .timer: return "Timer"
        case .focus: return "Focus"
        case .stopwatch: return "Stopwatch"
        case .clipboard: return "Clipboard"
        case .tray: return "File Tray"
        case .shortcuts: return "Shortcuts"
        case .awake: return "Keep Awake"
        case .moon: return "Moon"
        case .dice: return "Dice"
        case .counter: return "Counter"
        case .colors: return "Color Picker"
        }
    }

    var symbol: String {
        switch self {
        case .clock: return "clock.fill"
        case .analog: return "watch.analog"
        case .world: return "globe"
        case .media: return "play.circle.fill"
        case .weather: return "cloud.sun.fill"
        case .battery: return "battery.75percent"
        case .system: return "cpu"
        case .network: return "network"
        case .disk: return "internaldrive.fill"
        case .uptime: return "power"
        case .calendar: return "calendar.badge.clock"
        case .date: return "calendar.circle.fill"
        case .month: return "calendar"
        case .progress: return "chart.bar.fill"
        case .timer: return "timer"
        case .focus: return "brain.head.profile"
        case .stopwatch: return "stopwatch.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        case .tray: return "tray.full.fill"
        case .shortcuts: return "square.grid.2x2.fill"
        case .awake: return "cup.and.saucer.fill"
        case .moon: return "moon.stars.fill"
        case .dice: return "die.face.5.fill"
        case .counter: return "plus.forwardslash.minus"
        case .colors: return "eyedropper"
        }
    }

    /// The gallery icon's gradient, top to bottom.
    var colors: [Color] {
        switch self {
        case .clock: return [Color(red: 1, green: 0.62, blue: 0.2), Color(red: 0.95, green: 0.4, blue: 0.1)]
        case .analog: return [Color(white: 0.55), Color(white: 0.3)]
        case .world: return [Color(red: 0.3, green: 0.8, blue: 0.85), Color(red: 0.1, green: 0.5, blue: 0.7)]
        case .media: return [Color(red: 1, green: 0.3, blue: 0.45), Color(red: 0.6, green: 0.25, blue: 0.9)]
        case .weather: return [Color(red: 0.35, green: 0.7, blue: 1), Color(red: 0.1, green: 0.4, blue: 0.9)]
        case .battery: return [Color(red: 0.3, green: 0.85, blue: 0.4), Color(red: 0.1, green: 0.6, blue: 0.3)]
        case .system: return [Color(red: 0.35, green: 0.9, blue: 0.85), Color(red: 0.1, green: 0.6, blue: 0.6)]
        case .network: return [Color(red: 0.3, green: 0.55, blue: 1), Color(red: 0.2, green: 0.3, blue: 0.85)]
        case .disk: return [Color(red: 0.5, green: 0.5, blue: 0.95), Color(red: 0.3, green: 0.25, blue: 0.75)]
        case .uptime: return [Color(red: 0.45, green: 0.8, blue: 0.5), Color(red: 0.2, green: 0.5, blue: 0.35)]
        case .calendar: return [Color(red: 1, green: 0.4, blue: 0.4), Color(red: 0.85, green: 0.15, blue: 0.2)]
        case .date: return [Color(red: 1, green: 0.35, blue: 0.3), Color(red: 0.8, green: 0.1, blue: 0.15)]
        case .month: return [Color(red: 1, green: 0.5, blue: 0.35), Color(red: 0.9, green: 0.25, blue: 0.2)]
        case .progress: return [Color(red: 0.75, green: 0.45, blue: 1), Color(red: 0.5, green: 0.2, blue: 0.85)]
        case .timer: return [Color(red: 1, green: 0.7, blue: 0.2), Color(red: 1, green: 0.45, blue: 0.1)]
        case .focus: return [Color(red: 1, green: 0.35, blue: 0.3), Color(red: 0.85, green: 0.2, blue: 0.35)]
        case .stopwatch: return [Color(red: 1, green: 0.8, blue: 0.25), Color(red: 0.95, green: 0.55, blue: 0.1)]
        case .clipboard: return [Color(red: 0.3, green: 0.75, blue: 0.75), Color(red: 0.15, green: 0.5, blue: 0.55)]
        case .tray: return [Color(red: 0.35, green: 0.65, blue: 1), Color(red: 0.15, green: 0.45, blue: 0.95)]
        case .shortcuts: return [Color(red: 0.45, green: 0.45, blue: 1), Color(red: 0.75, green: 0.3, blue: 0.9)]
        case .awake: return [Color(red: 1, green: 0.85, blue: 0.3), Color(red: 0.9, green: 0.6, blue: 0.1)]
        case .moon: return [Color(red: 0.3, green: 0.3, blue: 0.6), Color(red: 0.1, green: 0.1, blue: 0.3)]
        case .dice: return [Color(red: 0.35, green: 0.85, blue: 0.55), Color(red: 0.1, green: 0.55, blue: 0.4)]
        case .counter: return [Color(red: 1, green: 0.45, blue: 0.7), Color(red: 0.85, green: 0.2, blue: 0.5)]
        case .colors: return [Color(red: 1, green: 0.6, blue: 0.2), Color(red: 0.55, green: 0.3, blue: 0.95)]
        }
    }

    /// Wide widgets take the room of two.
    var wide: Bool { self == .media || self == .calendar }
    var width: CGFloat { wide ? 222 : 108 }

    static let defaults: [HomeWidget] = [.clock, .media, .battery, .system]

    static func save(_ widgets: [HomeWidget]) -> String {
        widgets.map(\.rawValue).joined(separator: ",")
    }
}

/// One thing in the Home tab's row: a widget, or a separator. There can be any number of separators, each with its own
/// number so it can be told apart from the others.
enum HomeItem: Hashable, Identifiable {
    case widget(HomeWidget)
    case separator(Int)

    var id: String {
        switch self {
        case .widget(let widget): return widget.rawValue
        case .separator(let number): return "separator-\(number)"
        }
    }

    init?(id: String) {
        if let widget = HomeWidget(rawValue: id) {
            self = .widget(widget)
        } else if id.hasPrefix("separator-"), let number = Int(id.dropFirst("separator-".count)) {
            self = .separator(number)
        } else {
            return nil
        }
    }

    var width: CGFloat {
        if case .widget(let widget) = self { return widget.width }
        return 24
    }

    var title: String {
        if case .widget(let widget) = self { return widget.title }
        return "Separator"
    }

    /// A separator numbered after every one already in the row.
    static func newSeparator(in items: [HomeItem]) -> HomeItem {
        let numbers = items.compactMap { item -> Int? in
            if case .separator(let number) = item { return number }
            return nil
        }
        return .separator((numbers.max() ?? 0) + 1)
    }

    static func load(_ raw: String) -> [HomeItem] {
        var seen = Set<HomeItem>()
        return raw.split(separator: ",").compactMap { HomeItem(id: String($0)) }.filter { seen.insert($0).inserted }
    }

    static func save(_ items: [HomeItem]) -> String {
        items.map(\.id).joined(separator: ",")
    }
}

/// A widget being dragged: from the row to a new place, or from the gallery into the row.
private struct HomeDrag {
    let widget: HomeItem
    var location: CGPoint
    /// Whether it was already on the Home tab when the drag began.
    let wasPlaced: Bool
}

private struct WidgetFramesKey: PreferenceKey {
    static let defaultValue: [HomeItem: CGRect] = [:]
    static func reduce(value: inout [HomeItem: CGRect], nextValue: () -> [HomeItem: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// The Home tab: a row of live widgets. The pencil turns on arranging, Droppy-style: the widgets shrink, get dashed
/// outlines and drag into a new order, and a gallery of every widget slides up to drag (or click) more in.
struct HomeView: View {
    @EnvironmentObject var state: AppState
    @AppStorage(Prefs.homeWidgets) private var raw = HomeWidget.save(HomeWidget.defaults)
    @State private var snapshot: String?
    @State private var drag: HomeDrag?
    @State private var frames: [HomeItem: CGRect] = [:]

    private static let space = "home"
    private static let galleryHeight: CGFloat = 58
    private static let spring = Animation.spring(response: 0.35, dampingFraction: 0.8)

    var body: some View {
        let widgets = HomeItem.load(raw)
        let editing = state.editingHome
        GeometryReader { proxy in
            let full = proxy.size.height
            let rowHeight = editing ? max(full - Self.galleryHeight - 8, 40) : full
            let inset: CGFloat = editing ? 7 : 0
            let scale = max(rowHeight - inset * 2, 1) / max(full, 1)
            VStack(spacing: 8) {
                row(widgets, editing: editing, full: full, scale: scale, inset: inset, rowHeight: rowHeight, width: proxy.size.width)
                    .frame(height: rowHeight)
                if editing {
                    gallery(widgets, rowHeight: rowHeight)
                        .frame(height: Self.galleryHeight)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .coordinateSpace(name: Self.space)
            .overlay(alignment: .topLeading) {
                if let drag {
                    GalleryIcon(item: drag.widget, size: 46)
                        .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
                        .position(drag.location)
                        .allowsHitTesting(false)
                }
            }
            .onPreferenceChange(WidgetFramesKey.self) { frames = $0 }
        }
        .animation(Self.spring, value: editing)
        .onAppear {
            state.system.start()
            if widgets.contains(.widget(.calendar)) { state.calendar.activate() }
        }
        .onDisappear {
            state.system.stop()
            state.editingHome = false
        }
        .onChange(of: state.editingHome) { _, on in
            snapshot = on ? raw : nil
            drag = nil
        }
        .onChange(of: raw) { _, value in
            if HomeItem.load(value).contains(.widget(.calendar)) { state.calendar.activate() }
        }
    }

    // MARK: The row

    @ViewBuilder
    private func row(_ widgets: [HomeItem], editing: Bool, full: CGFloat, scale: CGFloat, inset: CGFloat,
                     rowHeight: CGFloat, width: CGFloat) -> some View {
        if widgets.isEmpty {
            if editing {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .overlay(
                        Text("Drag widgets here")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                    )
                    .padding(inset)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "square.grid.2x2").font(.system(size: 26))
                    Text("No widgets").font(.system(size: 14, weight: .semibold))
                    Text("Click the pencil to add some.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .foregroundStyle(.white.opacity(0.8))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10 * max(scale, 0.6)) {
                    ForEach(widgets) { widget in
                        slot(widget, editing: editing, full: full, scale: scale, rowHeight: rowHeight)
                            // A removed widget fades where it stood while the others close in on its space.
                            .transition(.scale(scale: 0.88).combined(with: .opacity))
                    }
                }
                .animation(Self.spring, value: widgets)
                .padding(inset)
                .frame(minWidth: width, maxHeight: .infinity)
            }
        }
    }

    private func slot(_ widget: HomeItem, editing: Bool, full: CGFloat, scale: CGFloat, rowHeight: CGFloat) -> some View {
        let lifted = drag?.widget == widget
        let shape = RoundedRectangle(cornerRadius: 18 * scale, style: .continuous)
        return ZStack {
            if lifted {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(GalleryIcon(item: widget, size: widget.width < 56 ? 20 : 56).opacity(0.45))
            } else if case .widget(let card) = widget {
                WidgetCard(widget: card)
                    .allowsHitTesting(!editing)
            } else {
                HomeSeparator()
            }
        }
        .frame(width: widget.width, height: full)
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: widget.width * scale, height: full * scale, alignment: .topLeading)
        .overlay {
            if editing {
                shape.strokeBorder(Color.white.opacity(lifted ? 0.7 : 0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .overlay(alignment: .topLeading) {
            if editing && !lifted {
                Button {
                    withAnimation(Self.spring) { remove(widget) }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.black)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.white))
                        .shadow(color: .black.opacity(0.4), radius: 2)
                }
                .buttonStyle(.plain)
                .offset(x: -6, y: -6)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .background(GeometryReader { geometry in
            Color.clear.preference(key: WidgetFramesKey.self, value: [widget: geometry.frame(in: .named(Self.space))])
        })
        .contentShape(Rectangle())
        .gesture(moveGesture(widget, rowHeight: rowHeight), including: editing ? .all : .subviews)
    }

    // MARK: The gallery

    private func gallery(_ widgets: [HomeItem], rowHeight: CGFloat) -> some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(HomeWidget.allCases) { widget in
                        let item = HomeItem.widget(widget)
                        GalleryTile(item: item, added: widgets.contains(item))
                            .opacity(drag?.widget == item ? 0.35 : 1)
                            .contentShape(Rectangle())
                            .onTapGesture { withAnimation(Self.spring) { toggle(item) } }
                            .gesture(galleryGesture(rowHeight: rowHeight) { item })
                            .help(widgets.contains(item) ? "Click to remove, or drag to move" : "Click to add, or drag into place")
                    }
                    // Any number of separators: each click or drag brings a new one.
                    GalleryTile(item: .separator(0), added: false)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(Self.spring) {
                                let items = HomeItem.load(raw)
                                raw = HomeItem.save(items + [HomeItem.newSeparator(in: items)])
                            }
                        }
                        .gesture(galleryGesture(rowHeight: rowHeight) { HomeItem.newSeparator(in: HomeItem.load(raw)) })
                        .help("Click to add a separator, or drag one into place")
                }
                .padding(.horizontal, 8)
            }
            Button {
                if let snapshot { raw = snapshot }
                state.editingHome = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .help("Cancel")
            Button {
                state.editingHome = false
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.blue))
                    .shadow(color: .blue.opacity(0.5), radius: 6)
            }
            .buttonStyle(.plain)
            .help("Done")
        }
        .padding(.trailing, 10)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
    }

    // MARK: Arranging

    private func moveGesture(_ widget: HomeItem, rowHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if drag == nil {
                    drag = HomeDrag(widget: widget, location: value.location, wasPlaced: true)
                } else {
                    drag?.location = value.location
                }
                place(widget, at: value.location, rowHeight: rowHeight)
            }
            .onEnded { value in
                withAnimation(Self.spring) {
                    // Dropped back on the gallery: take it off the Home tab.
                    if value.location.y > rowHeight + 4 { remove(widget) }
                    drag = nil
                }
            }
    }

    /// Dragging from the gallery. The item is decided as the drag begins, so a separator is a new one each time.
    private func galleryGesture(rowHeight: CGFloat, item: @escaping () -> HomeItem) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if drag == nil {
                    let widget = item()
                    drag = HomeDrag(widget: widget, location: value.location, wasPlaced: HomeItem.load(raw).contains(widget))
                } else {
                    drag?.location = value.location
                }
                if let widget = drag?.widget { place(widget, at: value.location, rowHeight: rowHeight) }
            }
            .onEnded { _ in
                withAnimation(Self.spring) { drag = nil }
            }
    }

    /// Puts the dragged widget where the pointer is in the row. A widget brought from the gallery leaves again if the
    /// pointer goes back down; one that was already placed keeps its spot until it is dropped.
    private func place(_ widget: HomeItem, at point: CGPoint, rowHeight: CGFloat) {
        let list = HomeItem.load(raw)
        var next = list.filter { $0 != widget }
        if point.y <= rowHeight + 4 {
            let index = next.filter { (frames[$0]?.midX ?? .greatestFiniteMagnitude) < point.x }.count
            next.insert(widget, at: min(index, next.count))
        } else if drag?.wasPlaced ?? true {
            return
        }
        if next != list {
            withAnimation(Self.spring) { raw = HomeItem.save(next) }
        }
    }

    private func toggle(_ widget: HomeItem) {
        let list = HomeItem.load(raw)
        raw = HomeItem.save(list.contains(widget) ? list.filter { $0 != widget } : list + [widget])
    }

    private func remove(_ widget: HomeItem) {
        raw = HomeItem.save(HomeItem.load(raw).filter { $0 != widget })
    }
}

/// A thin upright line between widgets on the Home tab.
struct HomeSeparator: View {
    var body: some View {
        Capsule()
            .fill(Color.white.opacity(0.18))
            .frame(width: 1.5)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A widget's icon in the gallery: a rounded square in its colours, like an app icon. A separator's is grey with a line.
struct GalleryIcon: View {
    let item: HomeItem
    let size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
        shape
            .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            .overlay {
                if case .widget(let widget) = item {
                    Image(systemName: widget.symbol)
                        .font(.system(size: size * 0.44, weight: .semibold))
                        .foregroundStyle(.white)
                } else {
                    Capsule().fill(Color.white).frame(width: max(size * 0.07, 1.5), height: size * 0.5)
                }
            }
            .overlay(shape.strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
            .frame(width: size, height: size)
    }

    private var colors: [Color] {
        if case .widget(let widget) = item { return widget.colors }
        return [Color(white: 0.55), Color(white: 0.32)]
    }
}

private struct GalleryTile: View {
    let item: HomeItem
    let added: Bool
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            GalleryIcon(item: item, size: 32)
                .overlay(alignment: .topTrailing) {
                    if added {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.white, .blue)
                            .offset(x: 5, y: -5)
                    }
                }
                .scaleEffect(hovering ? 1.08 : 1)
            Text(item.title)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(.white.opacity(added ? 0.5 : 0.85))
                .lineLimit(1)
                .frame(width: 54)
        }
        .padding(.vertical, 4)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}
