import AppKit
import SmarterShotCore

/// Passive full-screen dim shown for the duration of a recording, with a
/// see-through hole over the recorded region so it's always obvious what is
/// being captured. Purely visual:
/// - It ignores all mouse events, so the user can interact with the app being
///   recorded right through it.
/// - It never appears in the recording itself: window recordings capture only
///   the target window; ScreenCaptureKit area recordings exclude this app's
///   windows from the stream; and for the legacy `screencapture -R` path the
///   hole is truly transparent, so the captured region is untouched (the red
///   accent is stroked fully OUTSIDE the hole for the same reason).
final class RecordingDimOverlay {
    static let shared = RecordingDimOverlay()

    private var window: NSWindow?
    private var view: RecordingDimView?
    private var trackTimer: Timer?

    func show(for target: RecordingTarget) {
        hide()

        var union = NSRect.zero
        for s in NSScreen.screens { union = union == .zero ? s.frame : union.union(s.frame) }
        guard union != .zero else { return }

        let win = NSWindow(contentRect: union, styleMask: [.borderless], backing: .buffered, defer: false)
        // Just under the stop pill / preview overlays (both sit at .statusBar).
        win.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = false
        win.ignoresMouseEvents = true // clicks go to the app being recorded
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let v = RecordingDimView(frame: NSRect(origin: .zero, size: union.size))
        v.unionOrigin = union.origin
        v.holeCGRect = target.cgRect
        win.contentView = v
        win.orderFrontRegardless()

        window = win
        view = v

        // Window recordings follow the window if it moves or resizes.
        if case .window(let id, _) = target {
            trackTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                guard let self = self, let v = self.view else { return }
                let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]] ?? []
                guard let b = info.first?[kCGWindowBounds as String] as? [String: Any],
                      let r = CGRect(dictionaryRepresentation: b as CFDictionary) else { return }
                if r != v.holeCGRect { v.holeCGRect = r }
            }
        }
    }

    func hide() {
        trackTimer?.invalidate(); trackTimer = nil
        window?.orderOut(nil); window = nil; view = nil
    }
}

private final class RecordingDimView: NSView {
    var unionOrigin: NSPoint = .zero
    var holeCGRect: CGRect = .zero { didSet { needsDisplay = true } }

    /// Height of the primary display, used to flip CoreGraphics↔AppKit Y.
    private var flipH: CGFloat {
        (NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first)?.frame.height ?? 0
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0, alpha: SelectionOverlayStyle.recordingDimAlpha).setFill()
        bounds.fill()

        // CG→AppKit global (the Y flip is its own inverse), then into view coords.
        let g = ScreenGeometry.cgRect(fromAppKit: holeCGRect, primaryHeight: flipH)
        let hole = NSRect(x: g.minX - unionOrigin.x, y: g.minY - unionOrigin.y,
                          width: g.width, height: g.height)

        // Truly transparent hole — these pixels ARE the recording for the
        // legacy -R path, so nothing may be drawn over them. (This window
        // ignores mouse events, so alpha-0 click-through is irrelevant here.)
        NSColor.clear.set()
        hole.fill(using: .copy)

        // Recording accent, stroked fully outside the hole.
        NSColor.systemRed.withAlphaComponent(0.85).setStroke()
        let p = NSBezierPath(rect: hole.insetBy(dx: -2.5, dy: -2.5))
        p.lineWidth = 2
        p.stroke()
    }
}
