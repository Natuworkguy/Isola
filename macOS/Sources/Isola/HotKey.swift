import AppKit
import Carbon

/// The keyboard shortcut that opens and closes the island from anywhere: Control-Option-A.
final class HotKey {
    static let description = "⌃⌥A"
    static let signature = OSType(0x4154_4F4C)
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var pressed: (() -> Void)?

    func setEnabled(_ enabled: Bool) {
        enabled ? register() : unregister()
    }

    private func register() {
        guard hotKey == nil else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        let callback: EventHandlerUPP = { _, event, userData in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            // Every shortcut Isola registers comes through here: only this one is ours.
            var pressed = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            guard pressed.signature == HotKey.signature else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { hotKey.pressed?() }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &type, me, &handler)
        let id = EventHotKeyID(signature: HotKey.signature, id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_A), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKey)
    }

    private func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}
