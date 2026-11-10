// Global keyboard shortcut (Carbon hot keys need no extra permission).
import Carbon.HIToolbox

final class HotKey {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var installed = false
    private var ref: EventHotKeyRef?
    private let id: UInt32

    init?(keyCode: UInt32, modifiers: UInt32, id: UInt32, handler: @escaping () -> Void) {
        self.id = id
        Self.installHandler()
        let hkID = EventHotKeyID(signature: OSType(0x4E42_5448), id: id)   // 'NBTH'
        guard RegisterEventHotKey(keyCode, modifiers, hkID, GetApplicationEventTarget(), 0, &ref) == noErr else { return nil }
        Self.handlers[id] = handler
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        Self.handlers[id] = nil
    }

    private static func installHandler() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            DispatchQueue.main.async { HotKey.handlers[hk.id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

/// Sends ⌘V to whatever app is in front (needs Accessibility permission).
func pasteIntoFrontApp() {
    guard AXIsProcessTrusted() else { return }
    let src = CGEventSource(stateID: .combinedSessionState)
    let v = CGKeyCode(kVK_ANSI_V)
    let down = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: true)
    let up = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: false)
    down?.flags = .maskCommand
    up?.flags = .maskCommand
    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)
}
