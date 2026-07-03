import AppKit
import ApplicationServices

/// Detects when the user pastes (⌘V) the screenshot that is currently on the
/// clipboard, and auto-dismisses that overlay a few seconds later. The saved
/// file is untouched. Global key monitoring requires Accessibility permission;
/// without it this feature simply stays inactive.
final class PasteWatcher {
    static let shared = PasteWatcher()

    private var monitor: Any?
    private var promptedForAX = false
    private weak var lastOverlay: OverlayWindow?
    private var lastChangeCount = -1

    /// Call right after a shot has been copied to the clipboard.
    func noteCopied(overlay: OverlayWindow) {
        lastOverlay = overlay
        lastChangeCount = NSPasteboard.general.changeCount
        ensureMonitor()
    }

    /// Stop tracking an overlay (e.g. once it's dismissed).
    func forget(_ overlay: OverlayWindow) {
        if lastOverlay === overlay { lastOverlay = nil }
    }

    private func ensureMonitor() {
        guard monitor == nil else { return }

        let trusted = AXIsProcessTrusted()
        CaptureController.log("PasteWatcher.ensureMonitor trusted=\(trusted)")
        // Global key events require Accessibility trust. Prompt once.
        if !trusted && !promptedForAX {
            promptedForAX = true
            let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }

        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, let overlay = self.lastOverlay else { return }
            // Paste is ⌘V in most apps, but ⌃V in terminals like Claude Code.
            let mods = event.modifierFlags
            guard event.keyCode == 9, mods.contains(.command) || mods.contains(.control) else { return }
            // If the shot we last copied is still what's on the clipboard, the
            // user just pasted it — retire its overlay after a short delay.
            if NSPasteboard.general.changeCount == self.lastChangeCount {
                overlay.scheduleAutoDismiss(after: 5)
            }
        }
    }
}
