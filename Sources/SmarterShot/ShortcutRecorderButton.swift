import AppKit
import Carbon.HIToolbox

/// A button that records a keyboard shortcut: click it, then press the desired
/// combination. Rejects bare keys (a modifier is required) and Esc cancels.
///
/// Capture is done with a local NSEvent monitor rather than overriding keyDown,
/// because an NSButton does not reliably receive key events through the
/// responder chain — the monitor sees every key event delivered to the app.
final class ShortcutRecorderButton: NSButton {
    var shortcut: KeyboardShortcut {
        didSet { updateTitle() }
    }
    var onChange: ((KeyboardShortcut) -> Void)?

    private var recording = false {
        didSet { updateTitle() }
    }
    private var monitor: Any?

    init(shortcut: KeyboardShortcut) {
        self.shortcut = shortcut
        super.init(frame: .zero)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(toggleRecording)
        updateTitle()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    private func updateTitle() {
        title = recording ? "Type a shortcut…  (Esc to cancel)" : shortcut.displayString
    }

    @objc private func toggleRecording() {
        if recording { cancelRecording() } else { beginRecording() }
    }

    private func beginRecording() {
        guard !recording, monitor == nil else { return }
        recording = true
        // Ensure the app is active so the local monitor receives key events.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self = self, self.recording else { return event }
            return self.handle(event)
        }
    }

    /// Stops recording without changing the shortcut.
    func cancelRecording() {
        recording = false
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func carbonMods(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option)  { carbon |= UInt32(optionKey) }
        if flags.contains(.shift)   { carbon |= UInt32(shiftKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        return carbon
    }

    /// Returns nil to swallow the event (so recording keys never leak elsewhere).
    private func handle(_ event: NSEvent) -> NSEvent? {
        // On modifier changes, show a live preview so the user sees it listening.
        if event.type == .flagsChanged {
            let carbon = carbonMods(from: event.modifierFlags.intersection(.deviceIndependentFlagsMask))
            let preview = KeyboardShortcut(keyCode: 0, carbonModifiers: carbon, keyLabel: "…")
            title = carbon == 0 ? "Type a shortcut…  (Esc to cancel)" : preview.displayString
            return nil
        }
        guard event.type == .keyDown else { return nil }

        // Esc cancels.
        if event.keyCode == UInt16(kVK_Escape) {
            cancelRecording()
            return nil
        }

        let carbon = carbonMods(from: event.modifierFlags.intersection(.deviceIndependentFlagsMask))
        let candidate = KeyboardShortcut(keyCode: UInt32(event.keyCode),
                                         carbonModifiers: carbon,
                                         keyLabel: KeyLabelMap.label(for: event))

        // Require at least one modifier so a shortcut can't hijack plain typing.
        guard candidate.hasModifier else {
            NSSound.beep()
            return nil
        }

        shortcut = candidate
        cancelRecording()
        onChange?(candidate)
        return nil
    }

    deinit {
        if let monitor = monitor { NSEvent.removeMonitor(monitor) }
    }
}
