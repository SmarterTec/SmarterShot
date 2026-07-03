import AppKit
import Carbon.HIToolbox

/// Thin wrapper around Carbon's RegisterEventHotKey so we get a global keyboard
/// shortcut without needing Accessibility permission. A single application-wide
/// Carbon handler is installed once and shared by every instance.
final class HotKey {
    private var ref: EventHotKeyRef?
    private let id: UInt32
    private let callback: () -> Void

    private static var nextID: UInt32 = 1
    private static var registry: [UInt32: HotKey] = [:]
    private static var handlerInstalled = false

    /// - Parameters:
    ///   - keyCode: a virtual key code (e.g. kVK_ANSI_4).
    ///   - modifiers: Carbon modifier mask (cmdKey, shiftKey, optionKey, controlKey).
    /// Returns nil if the shortcut could not be registered (e.g. already taken).
    init?(keyCode: UInt32, modifiers: UInt32, callback: @escaping () -> Void) {
        self.callback = callback
        self.id = HotKey.nextID
        HotKey.nextID += 1

        HotKey.installHandlerIfNeeded()

        let signature: OSType = 0x53484b59 // 'SHKY'
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(keyCode,
                                         modifiers,
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &ref)
        guard status == noErr, ref != nil else { return nil }
        HotKey.registry[id] = self
    }

    /// Installs the shared Carbon event handler exactly once.
    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            guard let event = event else { return OSStatus(eventNotHandledErr) }
            var hkID = EventHotKeyID()
            let err = GetEventParameter(event,
                                        EventParamName(kEventParamDirectObject),
                                        EventParamType(typeEventHotKeyID),
                                        nil,
                                        MemoryLayout<EventHotKeyID>.size,
                                        nil,
                                        &hkID)
            if err == noErr {
                HotKey.registry[hkID.id]?.callback()
            }
            return noErr
        }, 1, &eventType, nil, nil)
    }

    func invalidate() {
        if let ref = ref {
            UnregisterEventHotKey(ref)
            self.ref = nil
        }
        HotKey.registry[id] = nil
    }

    deinit { invalidate() }
}
