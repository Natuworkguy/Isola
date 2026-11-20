import AppKit
import ApplicationServices

/// Moving the front window into a half, a quarter or a third of its screen, filling it, or centring it, from the
/// keyboard (⌃⌥ and an arrow, U I J K, D F G, Return or C) or the Ring. Needs Accessibility, like the media keys.
enum WindowSnap {
    enum Spot: String, CaseIterable {
        case left, right, top, bottom, maximize, center
        case topLeft, topRight, bottomLeft, bottomRight
        case thirdLeft, thirdCenter, thirdRight

        var title: String {
            switch self {
            case .left: return "Left Half"
            case .right: return "Right Half"
            case .top: return "Top Half"
            case .bottom: return "Bottom Half"
            case .maximize: return "Fill Screen"
            case .center: return "Centre"
            case .topLeft: return "Top Left"
            case .topRight: return "Top Right"
            case .bottomLeft: return "Bottom Left"
            case .bottomRight: return "Bottom Right"
            case .thirdLeft: return "Left Third"
            case .thirdCenter: return "Middle Third"
            case .thirdRight: return "Right Third"
            }
        }

        /// Where it goes in a screen's usable area (Cocoa coordinates, origin bottom left).
        func rect(in area: CGRect, current: CGSize) -> CGRect {
            let w = area.width, h = area.height, x = area.minX, y = area.minY
            switch self {
            case .left: return CGRect(x: x, y: y, width: w / 2, height: h)
            case .right: return CGRect(x: x + w / 2, y: y, width: w / 2, height: h)
            case .top: return CGRect(x: x, y: y + h / 2, width: w, height: h / 2)
            case .bottom: return CGRect(x: x, y: y, width: w, height: h / 2)
            case .maximize: return area
            case .center:
                let size = CGSize(width: min(current.width, w), height: min(current.height, h))
                return CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2,
                              width: size.width, height: size.height)
            case .topLeft: return CGRect(x: x, y: y + h / 2, width: w / 2, height: h / 2)
            case .topRight: return CGRect(x: x + w / 2, y: y + h / 2, width: w / 2, height: h / 2)
            case .bottomLeft: return CGRect(x: x, y: y, width: w / 2, height: h / 2)
            case .bottomRight: return CGRect(x: x + w / 2, y: y, width: w / 2, height: h / 2)
            case .thirdLeft: return CGRect(x: x, y: y, width: w / 3, height: h)
            case .thirdCenter: return CGRect(x: x + w / 3, y: y, width: w / 3, height: h)
            case .thirdRight: return CGRect(x: x + 2 * w / 3, y: y, width: w / 3, height: h)
            }
        }
    }

    static func snap(_ spot: Spot) {
        guard AXIsProcessTrusted() else {
            let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
            AppState.shared.showBanner(IslandBanner(
                symbol: "rectangle.split.2x1", tint: .orange, title: "Isola needs Accessibility",
                subtitle: "To move windows: System Settings, Privacy & Security"), for: 4)
            return
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        let owner = AXUIElementCreateApplication(app.processIdentifier)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(owner, kAXFocusedWindowAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return }
        let window = focused as! AXUIElement

        // AX positions are measured from the top left of the main screen, y going down; Cocoa's from the bottom left.
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let position = point(of: window), size = self.size(of: window)
        let cocoaFrame = CGRect(x: position.x, y: mainHeight - position.y - size.height,
                                width: size.width, height: size.height)
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: cocoaFrame.midX, y: cocoaFrame.midY)) }
            ?? NSScreen.main ?? NSScreen.screens[0]
        let target = spot.rect(in: screen.visibleFrame, current: size).integral
        var axOrigin = CGPoint(x: target.minX, y: mainHeight - target.maxY)
        var axSize = CGSize(width: target.width, height: target.height)
        // Moved, sized, then moved again: an app with a minimum size may have pushed it off the first time.
        if let value = AXValueCreate(.cgPoint, &axOrigin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        }
        if let value = AXValueCreate(.cgSize, &axSize) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
        }
        if let value = AXValueCreate(.cgPoint, &axOrigin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        }
    }

    private static func point(of window: AXUIElement) -> CGPoint {
        var value: CFTypeRef?
        var point = CGPoint.zero
        if AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &value) == .success, let value,
           CFGetTypeID(value) == AXValueGetTypeID() {
            AXValueGetValue(value as! AXValue, .cgPoint, &point)
        }
        return point
    }

    private static func size(of window: AXUIElement) -> CGSize {
        var value: CFTypeRef?
        var size = CGSize.zero
        if AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &value) == .success, let value,
           CFGetTypeID(value) == AXValueGetTypeID() {
            AXValueGetValue(value as! AXValue, .cgSize, &size)
        }
        return size
    }
}
