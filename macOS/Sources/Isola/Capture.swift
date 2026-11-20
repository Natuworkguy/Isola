import AppKit
import SwiftUI

/// Capturing part of the screen: drawn on in Isola's markup window (⌃⌥⇧S), or read for its text, which is copied
/// (⌃⌥⇧T). The area is picked with macOS's own crosshair; Escape cancels.
enum Capture {
    static func markup() {
        area { image in MarkupWindow.show(image) }
    }

    static func text() {
        area { image in OCR.copyText(of: image) }
    }

    /// Lets the user pick an area (or, pressing Space, a window) and hands back its picture, unless cancelled.
    static func area(_ then: @escaping (NSImage) -> Void) {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("isola-capture-\(UUID().uuidString).png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", "-o", file.path]
        process.terminationHandler = { _ in
            DispatchQueue.main.async {
                defer { try? FileManager.default.removeItem(at: file) }
                guard let data = try? Data(contentsOf: file), let image = NSImage(data: data) else { return }
                then(image)
            }
        }
        do {
            try process.run()
        } catch {
            AppState.shared.showBanner(IslandBanner(symbol: "camera.viewfinder", tint: .orange,
                                                    title: "Couldn't capture the screen", subtitle: ""), for: 3)
        }
    }
}

/// The window a capture opens in, to draw on and then copy, save or put in the tray.
enum MarkupWindow {
    private static var windows: [NSWindow] = []

    static func show(_ image: NSImage) {
        let pixels = image.representations.first.map { CGSize(width: $0.pixelsWide, height: $0.pixelsHigh) }
            ?? image.size
        // Shown at most 960 by 640, never bigger than the capture itself (in points).
        let fit = min(1, 960 / max(1, image.size.width), 640 / max(1, image.size.height))
        let shown = CGSize(width: max(360, image.size.width * fit), height: max(200, image.size.height * fit))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: CGSize(width: shown.width + 32, height: shown.height + 96)),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.title = "Markup"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.contentView = NSHostingView(rootView: MarkupView(image: image, pixels: pixels, shown: shown) {
            window.close()
        })
        window.center()
        windows.append(window)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window,
                                               queue: .main) { _ in windows.removeAll { $0 === window } }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

struct Mark: Identifiable {
    enum Tool: String, CaseIterable, Identifiable {
        case pen, arrow, box, highlight, blur, text
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .pen: return "scribble"
            case .arrow: return "arrow.up.right"
            case .box: return "rectangle"
            case .highlight: return "highlighter"
            case .blur: return "drop.halffull"
            case .text: return "textformat"
            }
        }
        var title: String {
            switch self {
            case .pen: return "Pen"
            case .arrow: return "Arrow"
            case .box: return "Box"
            case .highlight: return "Highlighter"
            case .blur: return "Blur"
            case .text: return "Text"
            }
        }
    }

    let id = UUID()
    var tool: Tool
    var color: Color
    /// Where it was drawn, as fractions of the picture (0...1), so it scales to any size.
    var points: [CGPoint]
    var text = ""

    var rect: CGRect {
        guard let first = points.first, let last = points.last else { return .zero }
        return CGRect(x: min(first.x, last.x), y: min(first.y, last.y),
                      width: abs(last.x - first.x), height: abs(last.y - first.y))
    }
}

/// The picture with its marks on it, at SIZE: the same view is shown in the window and rendered to save.
struct MarkupCanvas: View {
    let image: NSImage
    let marks: [Mark]
    let size: CGSize

    var body: some View {
        let scale = size.width / 900
        ZStack(alignment: .topLeading) {
            Image(nsImage: image).resizable().frame(width: size.width, height: size.height)
            ForEach(marks.filter { $0.tool == .blur }) { mark in
                let r = denormal(mark.rect)
                Image(nsImage: image).resizable().frame(width: size.width, height: size.height)
                    .blur(radius: 14 * max(1, scale), opaque: true)
                    .mask(alignment: .topLeading) {
                        Rectangle().frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
                    }
            }
            Canvas { context, _ in
                for mark in marks where mark.tool != .blur && mark.tool != .text {
                    draw(mark, in: &context, scale: scale)
                }
            }
            .frame(width: size.width, height: size.height)
            ForEach(marks.filter { $0.tool == .text }) { mark in
                if let at = mark.points.first {
                    Text(mark.text)
                        .font(.system(size: 22 * max(0.6, scale), weight: .bold, design: .rounded))
                        .foregroundStyle(mark.color)
                        .shadow(color: .black.opacity(0.35), radius: 2 * scale, y: 1)
                        .fixedSize()
                        .offset(x: at.x * size.width, y: at.y * size.height - 14 * max(0.6, scale))
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private func denormal(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX * size.width, y: r.minY * size.height, width: r.width * size.width, height: r.height * size.height)
    }

    private func draw(_ mark: Mark, in context: inout GraphicsContext, scale: CGFloat) {
        let pts = mark.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        guard let first = pts.first, let last = pts.last else { return }
        let width = 4 * max(0.6, scale)
        switch mark.tool {
        case .pen, .highlight:
            var path = Path()
            path.addLines(pts)
            let highlight = mark.tool == .highlight
            context.stroke(path, with: .color(mark.color.opacity(highlight ? 0.38 : 1)),
                           style: StrokeStyle(lineWidth: highlight ? width * 5 : width, lineCap: .round, lineJoin: .round))
        case .box:
            let r = CGRect(x: min(first.x, last.x), y: min(first.y, last.y),
                           width: abs(last.x - first.x), height: abs(last.y - first.y))
            context.stroke(Path(roundedRect: r, cornerRadius: 4 * scale), with: .color(mark.color), lineWidth: width)
        case .arrow:
            var path = Path()
            path.move(to: first)
            path.addLine(to: last)
            let angle = atan2(last.y - first.y, last.x - first.x), head = 18 * max(0.6, scale)
            var tip = Path()
            tip.move(to: last)
            tip.addLine(to: CGPoint(x: last.x - head * cos(angle - .pi / 7), y: last.y - head * sin(angle - .pi / 7)))
            tip.addLine(to: CGPoint(x: last.x - head * cos(angle + .pi / 7), y: last.y - head * sin(angle + .pi / 7)))
            tip.closeSubpath()
            context.stroke(path, with: .color(mark.color), style: StrokeStyle(lineWidth: width, lineCap: .round))
            context.fill(tip, with: .color(mark.color))
        case .blur, .text:
            break
        }
    }
}

struct MarkupView: View {
    let image: NSImage
    let pixels: CGSize
    let shown: CGSize
    let done: () -> Void

    @State private var tool: Mark.Tool = .arrow
    @State private var color: Color = .red
    @State private var marks: [Mark] = []
    @State private var drawing: Mark?
    @State private var typingAt: CGPoint?
    @State private var typed = ""
    @State private var status = ""
    @FocusState private var typing: Bool

    private let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .white, .black]

    var body: some View {
        VStack(spacing: 12) {
            toolbar
            ZStack(alignment: .topLeading) {
                MarkupCanvas(image: image, marks: marks + (drawing.map { [$0] } ?? []), size: shown)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
                    .gesture(drawGesture)
                if let at = typingAt {
                    TextField("Type", text: $typed)
                        .textFieldStyle(.plain)
                        .font(.system(size: 22 * max(0.6, shown.width / 900), weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                        .frame(width: 260)
                        .focused($typing)
                        .offset(x: at.x * shown.width, y: at.y * shown.height - 14)
                        .onSubmit(commitText)
                }
            }
            .frame(width: shown.width, height: shown.height)
            HStack {
                Text(status).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Copy Text") { OCR.copyText(of: rendered()); status = "Reading the text…" }
                Button("Add to Tray") { addToTray() }
                Button("Save") { save() }
                Button("Copy") { copy() }
                    .keyboardShortcut("c", modifiers: .command)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker("", selection: $tool) {
                ForEach(Mark.Tool.allCases) { Image(systemName: $0.symbol).help($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 270)
            Divider().frame(height: 18)
            ForEach(colors, id: \.self) { swatch in
                Button { color = swatch } label: {
                    Circle().fill(swatch).frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(.white.opacity(color == swatch ? 1 : 0.25), lineWidth: color == swatch ? 2.5 : 1))
                        .shadow(color: .black.opacity(0.3), radius: 1)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button { if !marks.isEmpty { marks.removeLast() } } label: { Image(systemName: "arrow.uturn.backward") }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(marks.isEmpty)
                .help("Undo")
        }
    }

    private var drawGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let p = CGPoint(x: min(max(value.location.x / shown.width, 0), 1),
                                y: min(max(value.location.y / shown.height, 0), 1))
                if tool == .text { return }
                if drawing == nil { drawing = Mark(tool: tool, color: color, points: [p]) }
                if tool == .pen || tool == .highlight {
                    drawing?.points.append(p)
                } else {
                    drawing?.points = [drawing?.points.first ?? p, p]
                }
            }
            .onEnded { value in
                if tool == .text {
                    commitText()
                    typingAt = CGPoint(x: value.location.x / shown.width, y: value.location.y / shown.height)
                    typed = ""
                    typing = true
                    return
                }
                if let mark = drawing, mark.points.count > 1 { marks.append(mark) }
                drawing = nil
            }
    }

    private func commitText() {
        if let at = typingAt, !typed.trimmingCharacters(in: .whitespaces).isEmpty {
            marks.append(Mark(tool: .text, color: color, points: [at], text: typed))
        }
        typingAt = nil
        typed = ""
    }

    /// The picture with its marks, at the capture's full resolution.
    private func rendered() -> NSImage {
        commitText()
        let renderer = ImageRenderer(content: MarkupCanvas(image: image, marks: marks, size: pixels))
        renderer.scale = 1
        return renderer.nsImage ?? image
    }

    private func copy() {
        let picture = rendered()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([picture])
        AppState.shared.showBanner(IslandBanner(symbol: "doc.on.clipboard.fill", tint: .green,
                                                title: "Copied the capture", subtitle: ""), for: 2)
        done()
    }

    private func write() -> URL? {
        let picture = rendered()
        guard let tiff = picture.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
        let url = FileActions.uniqueURL(in: FileActions.downloads, base: "Capture \(stamp)", extension: "png")
        return (try? png.write(to: url)) != nil ? url : nil
    }

    private func save() {
        guard let url = write() else { status = "Couldn't save it"; return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        done()
    }

    private func addToTray() {
        guard let url = write() else { status = "Couldn't save it"; return }
        AppState.shared.tray.add([url])
        AppState.shared.showBanner(IslandBanner(symbol: "tray.and.arrow.down.fill", tint: .blue,
                                                title: "Added to the tray", subtitle: url.lastPathComponent), for: 2.5)
        done()
    }
}
