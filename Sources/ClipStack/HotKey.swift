import AppKit
import Carbon.HIToolbox

/// Minimal Carbon-based global hotkey registry (no Accessibility permission
/// required, unlike CGEvent taps).
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var handlers: [UInt32: () -> Void] = [:]
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var handlerInstalled = false

    private static let signature: OSType = {
        var value: OSType = 0
        for byte in "CLPS".utf8 { value = (value << 8) + OSType(byte) }
        return value
    }()

    @discardableResult
    func register(keyCode: UInt32, carbonModifiers: UInt32, handler: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(keyCode, carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            NSLog("ClipStack: RegisterEventHotKey failed with status \(status)")
            return false
        }
        handlers[id] = handler
        hotKeyRefs[id] = ref
        return true
    }

    fileprivate func fire(id: UInt32) {
        handlers[id]?()
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // C function pointer: must not capture context, hence the singleton.
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            DispatchQueue.main.async { HotKeyCenter.shared.fire(id: hotKeyID.id) }
            return noErr
        }, 1, &spec, nil, nil)
        handlerInstalled = true
    }
}
