import AppKit
import Carbon

/// The keyboard shortcuts of Isola's tools, all with Control and Option, like ⌃⌥A for the island: the Ring, capturing
/// the screen or the text on it, dictation, muting a call, and snapping windows. Each tool can be turned off in
/// Settings, and then its keys are left free for other apps.
final class Shortcuts {
    static let shared = Shortcuts()
    static let signature = OSType(0x4953_4F54)  // "ISOT"

    enum Action: UInt32, CaseIterable {
        case ring = 10, capture, captureText, dictate, mute
        case snapLeft, snapRight, snapTop, snapBottom, maximize, center
        case topLeft, topRight, bottomLeft, bottomRight, thirdLeft, thirdCenter, thirdRight

        var key: Int {
            switch self {
            case .ring: return kVK_Space
            case .capture: return kVK_ANSI_S
            case .captureText: return kVK_ANSI_T
            case .dictate: return kVK_ANSI_D
            case .mute: return kVK_ANSI_M
            case .snapLeft: return kVK_LeftArrow
            case .snapRight: return kVK_RightArrow
            case .snapTop: return kVK_UpArrow
            case .snapBottom: return kVK_DownArrow
            case .maximize: return kVK_Return
            case .center: return kVK_ANSI_C
            case .topLeft: return kVK_ANSI_U
            case .topRight: return kVK_ANSI_I
            case .bottomLeft: return kVK_ANSI_J
            case .bottomRight: return kVK_ANSI_K
            case .thirdLeft: return kVK_ANSI_D
            case .thirdCenter: return kVK_ANSI_F
            case .thirdRight: return kVK_ANSI_G
            }
        }

        /// Capturing, dictation and muting add Shift, so ⌃⌥D and ⌃⌥T stay with window thirds.
        var shifted: Bool { [.capture, .captureText, .dictate, .mute].contains(self) }

        var label: String {
            let keys: [Action: String] = [
                .ring: "Space", .capture: "S", .captureText: "T", .dictate: "D", .mute: "M",
                .snapLeft: "←", .snapRight: "→", .snapTop: "↑", .snapBottom: "↓", .maximize: "↩", .center: "C",
                .topLeft: "U", .topRight: "I", .bottomLeft: "J", .bottomRight: "K",
                .thirdLeft: "D", .thirdCenter: "F", .thirdRight: "G",
            ]
            return "⌃⌥" + (shifted ? "⇧" : "") + (keys[self] ?? "")
        }

        /// The setting that turns it on.
        var pref: String {
            switch self {
            case .ring: return Prefs.toolRing
            case .capture: return Prefs.toolCapture
            case .captureText: return Prefs.toolCaptureText
            case .dictate: return Prefs.toolDictate
            case .mute: return Prefs.liveCalls
            default: return Prefs.toolSnap
            }
        }

        func perform() {
            switch self {
            case .ring: RingMenu.shared.toggle()
            case .capture: Capture.markup()
            case .captureText: Capture.text()
            case .dictate: Dictation.shared.toggle()
            case .mute: CallControls.shared.toggleMute()
            case .snapLeft: WindowSnap.snap(.left)
            case .snapRight: WindowSnap.snap(.right)
            case .snapTop: WindowSnap.snap(.top)
            case .snapBottom: WindowSnap.snap(.bottom)
            case .maximize: WindowSnap.snap(.maximize)
            case .center: WindowSnap.snap(.center)
            case .topLeft: WindowSnap.snap(.topLeft)
            case .topRight: WindowSnap.snap(.topRight)
            case .bottomLeft: WindowSnap.snap(.bottomLeft)
            case .bottomRight: WindowSnap.snap(.bottomRight)
            case .thirdLeft: WindowSnap.snap(.thirdLeft)
            case .thirdCenter: WindowSnap.snap(.thirdCenter)
            case .thirdRight: WindowSnap.snap(.thirdRight)
            }
        }
    }

    private var registered: [Action: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?

    /// Registers the shortcuts of the tools that are on, and again whenever the settings change.
    func start() {
        install()
        apply()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil,
                                               queue: .main) { [weak self] _ in self?.apply() }
    }

    private func install() {
        guard handler == nil else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, _ in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var pressed = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            guard pressed.signature == Shortcuts.signature, let action = Action(rawValue: pressed.id)
            else { return OSStatus(eventNotHandledErr) }
            DispatchQueue.main.async { action.perform() }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &type, nil, &handler)
    }

    private func apply() {
        for action in Action.allCases {
            let on = UserDefaults.standard.bool(forKey: action.pref)
            if on, registered[action] == nil {
                var ref: EventHotKeyRef?
                let modifiers = UInt32(controlKey | optionKey | (action.shifted ? shiftKey : 0))
                let id = EventHotKeyID(signature: Shortcuts.signature, id: action.rawValue)
                if RegisterEventHotKey(UInt32(action.key), modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr,
                   let ref {
                    registered[action] = ref
                }
            } else if !on, let ref = registered[action] {
                UnregisterEventHotKey(ref)
                registered[action] = nil
            }
        }
    }
}
