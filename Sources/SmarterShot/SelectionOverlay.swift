import AppKit
import QuartzCore
import SmarterShotCore

/// A full-screen dimmed overlay for choosing what to record:
/// - `.area`: drag a rectangle.
/// - `.window`: hover to highlight the window under the cursor, click to pick it.
/// Esc cancels. The completion returns the picked `RecordingTarget`,
/// or nil if cancelled.
final class SelectionOverlay: NSObject {
    enum Mode { case area, window }

    private static var current: SelectionOverlay?

    static func present(mode: Mode, fullPage: ((CGWindowID, CGRect) -> Void)? = nil, completion: @escaping (RecordingTarget?) -> Void) {
        current?.finish(nil)
        let overlay = SelectionOverlay(mode: mode, fullPage: fullPage, completion: completion)
        current = overlay
        overlay.show()
    }

    private let mode: Mode
    private let completion: (RecordingTarget?) -> Void
    private var window: KeyableWindow!
    private var view: SelectionView!
    private var keyMonitor: Any?
    private var finished = false
    private let fullPage: ((CGWindowID, CGRect) -> Void)?

    private init(mode: Mode, fullPage: ((CGWindowID, CGRect) -> Void)?, completion: @escaping (RecordingTarget?) -> Void) {
        self.mode = mode
        self.fullPage = fullPage
        self.completion = completion
        super.init()
        build()
    }

    private func build() {
        var union = NSRect.zero
        for s in NSScreen.screens { union = union == .zero ? s.frame : union.union(s.frame) }

        window = KeyableWindow(contentRect: union, styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = "Select Window"
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // CRITICAL: a transparent window gets per-pixel hit-testing from the
        // window server — clicks on fully transparent pixels fall through to the
        // window beneath. In window mode we cut a see-through hole over the
        // hovered window (exactly where the user clicks), so without this the
        // click went straight through to the target app and selection never
        // fired. Setting ignoresMouseEvents explicitly to false opts out of the
        // per-pixel behavior and routes every click in the frame to us.
        window.ignoresMouseEvents = false

        view = SelectionView(frame: NSRect(origin: .zero, size: union.size))
        view.mode = mode
        view.unionOrigin = union.origin
        view.onFinish = { [weak self] target in self?.finish(target) }
        if fullPage != nil {
            view.onFullPage = { [weak self] id, rect in
                guard let self = self, !self.finished else { return }
                self.finish(nil, notify: false)
                DispatchQueue.main.asyncAfter(deadline: .now()+0.15) { self.fullPage?(id, rect) }
            }
        }
        window.contentView = view
    }

    private func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        // Reliable Esc-to-cancel regardless of first-responder state.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.finish(nil); return nil }
            return event
        }
    }

    private func finish(_ target: RecordingTarget?, notify: Bool = true) {
        guard !finished else { return }; finished = true
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        view?.cancelDetection()
        window?.orderOut(nil)
        if SelectionOverlay.current === self { SelectionOverlay.current = nil }
        if notify { completion(target) }
    }
}

/// Borderless windows can't become key by default; we need key for Esc/mouse.
final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class SelectionView: NSView {
    var mode: SelectionOverlay.Mode = .area
    var unionOrigin: NSPoint = .zero
    var onFinish: ((RecordingTarget?) -> Void)?
    var onFullPage: ((CGWindowID, CGRect) -> Void)? { didSet { configureFullPage() } }
    private var fullPageButton: NSButton?
    private var availabilityTask: Task<Void,Never>?
    private var availabilityWindow: CGWindowID?
    private var availability: [CGWindowID:Bool] = [:]
    private func configureFullPage() {
        guard onFullPage != nil else { return }
        let button = FullPageButton(title: "Full Page", target: self, action: #selector(chooseFullPage))
        button.bezelStyle = .rounded
        if #available(macOS 26.0, *) { button.bezelStyle = .glass; button.borderShape = .capsule }
        button.image = NSImage(systemSymbolName:"arrow.down.to.line",accessibilityDescription:nil)
        button.imagePosition = .imageLeading
        button.contentTintColor = .controlAccentColor
        button.toolTip = "Scroll and capture the entire page (Shift-click the window). Requires Accessibility access."
        button.setAccessibilityLabel("Capture Full Page")
        addSubview(button); fullPageButton = button; updateFullPagePosition()
    }
    private func updateFullPagePosition() {
        guard let button = fullPageButton else { return }
        guard let hovered = hoverWindow else { button.isHidden = true; (button as? FullPageButton)?.updateAttention(); return }
        if availabilityWindow != hovered.id {
            availabilityWindow = hovered.id
            availabilityTask?.cancel()
            if availability[hovered.id] == nil {
                button.isEnabled = false
                availabilityTask = Task { @MainActor [weak self] in
                    let supported = await ScrollCapture.supports(windowID:hovered.id,frame:hovered.cgRect)
                    guard !Task.isCancelled, let self = self else { return }
                    self.availability[hovered.id] = supported
                    self.updateFullPagePosition()
                }
            }
        }
        button.isEnabled = availability[hovered.id] == true
        button.isHidden = availability[hovered.id] == false
        let rect = cgToView(hovered.cgRect)
        button.frame = NSRect(x: max(12, min(bounds.width-132, rect.midX-60)),
            y: max(12, min(bounds.height-48, rect.maxY-52)), width: 120, height: 36)
        (button as? FullPageButton)?.updateAttention()
    }
    func cancelDetection() { availabilityTask?.cancel(); availabilityTask = nil; (fullPageButton as? FullPageButton)?.stopAttention() }
    @objc private func chooseFullPage() {
        if let hovered = hoverWindow { onFullPage?(hovered.id, hovered.cgRect) }
    }

    private var dragStart: NSPoint?     // global (AppKit)
    private var dragCurrent: NSPoint?
    private var hoverWindow: (id: CGWindowID, cgRect: CGRect)?

    override var acceptsFirstResponder: Bool { true }

    // SmarterShot is a background (LSUIElement) app, so this overlay usually
    // isn't the "active" app when the user clicks a window. Without this, AppKit
    // treats that first click as an app-activation click and swallows it instead
    // of delivering mouseDown/mouseUp — hover highlights, but clicking a window
    // does nothing. Returning true delivers the click so the pick actually runs.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        if mode == .area { addCursorRect(bounds, cursor: .crosshair) }
    }

    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseMoved, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
        if mode == .window { hoverWindow = windowUnderCursor(); updateFullPagePosition(); needsDisplay = true }
    }

    /// Height of the primary display, used to flip AppKit↔CoreGraphics Y.
    private var flipH: CGFloat {
        (NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first)?.frame.height ?? 0
    }

    private func cgToView(_ r: CGRect) -> NSRect {
        let globalY = flipH - (r.origin.y + r.height)
        return NSRect(x: r.origin.x - unionOrigin.x, y: globalY - unionOrigin.y,
                      width: r.width, height: r.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0, alpha: SelectionOverlayStyle.dimAlpha).setFill()
        bounds.fill()

        var hole: NSRect?
        if mode == .area, let s = dragStart, let c = dragCurrent {
            hole = NSRect(x: min(s.x, c.x) - unionOrigin.x, y: min(s.y, c.y) - unionOrigin.y,
                          width: abs(s.x - c.x), height: abs(s.y - c.y))
        } else if mode == .window, let hw = hoverWindow {
            hole = cgToView(hw.cgRect)
        }
        if let h = hole {
            // Near-clear, but NOT alpha 0: fully transparent pixels are
            // click-through at the window server, and this hole is exactly
            // where the user clicks to pick a window (see SelectionOverlayStyle).
            NSColor(white: 0, alpha: SelectionOverlayStyle.holeAlpha).set()
            h.fill(using: .copy)
            NSColor.white.withAlphaComponent(0.95).setStroke()
            let p = NSBezierPath(rect: h); p.lineWidth = 2; p.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        if mode == .area { dragStart = NSEvent.mouseLocation; dragCurrent = dragStart }
    }
    override func mouseDragged(with event: NSEvent) {
        if mode == .area { dragCurrent = NSEvent.mouseLocation; needsDisplay = true }
        else { hoverWindow = windowUnderCursor(); updateFullPagePosition(); needsDisplay = true }
    }
    override func mouseMoved(with event: NSEvent) {
        if mode == .window { hoverWindow = windowUnderCursor(); updateFullPagePosition(); needsDisplay = true }
    }
    override func mouseUp(with event: NSEvent) {
        if mode == .area {
            guard let s = dragStart, let c = dragCurrent else { onFinish?(nil); return }
            let g = NSRect(x: min(s.x, c.x), y: min(s.y, c.y), width: abs(s.x - c.x), height: abs(s.y - c.y))
            guard g.width >= 8, g.height >= 8 else { onFinish?(nil); return }
            let cg = ScreenGeometry.cgRect(fromAppKit: g, primaryHeight: flipH)
            onFinish?(.area(cg))
        } else {
            // Look up the window under the cursor fresh at click time.
            if let hw = windowUnderCursor() ?? hoverWindow {
                CaptureController.log("WINDOW PICK id=\(hw.id) rect=\(hw.cgRect)")
                if event.modifierFlags.contains(.shift), onFullPage != nil { onFullPage?(hw.id, hw.cgRect) }
                else { onFinish?(.window(hw.id, hw.cgRect)) }
            } else {
                CaptureController.log("WINDOW PICK failed — no window under cursor")
                onFinish?(nil)
            }
        }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onFinish?(nil) } // Esc
    }

    private func windowUnderCursor() -> (id: CGWindowID, cgRect: CGRect)? {
        let mouse = NSEvent.mouseLocation
        let point = ScreenGeometry.cgPoint(fromAppKit: mouse, primaryHeight: flipH)
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                              kCGNullWindowID) as? [[String: Any]] ?? []
        // Skip every window this app owns (the full-screen overlay lives above
        // the target and must never be picked). Excluding by number is reliable
        // even when owner names are redacted without Screen Recording access.
        let ownNumbers = Set(NSApp.windows.map { Int($0.windowNumber) })
        return WindowPicker.windowUnder(point: point, in: list, ownWindowNumbers: ownNumbers)
    }
}

/// An accent outline and glint guide discovery without replacing the native
/// glass button. The system keeps its normal hover/press feedback.
private final class FullPageButton:NSButton {
    private let shimmer = CAGradientLayer()
    private let outline = CAShapeLayer()
    private var accessibilityObserver:NSObjectProtocol?
    override init(frame:NSRect) { super.init(frame:frame); configureAttention() }
    required init?(coder:NSCoder) { super.init(coder:coder); configureAttention() }
    private func configureAttention() {
        wantsLayer = true
        shimmer.startPoint = CGPoint(x:0,y:0.5); shimmer.endPoint = CGPoint(x:1,y:0.5)
        shimmer.colors = [NSColor.clear.cgColor,NSColor.controlAccentColor.withAlphaComponent(0.95).cgColor,NSColor.clear.cgColor]
        shimmer.locations = [-1,-0.5,0]
        outline.fillColor = NSColor.clear.cgColor; outline.strokeColor = NSColor.white.cgColor; outline.lineWidth = 2
        shimmer.mask = outline; layer?.addSublayer(shimmer)
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,object:nil,queue:.main) { [weak self] _ in self?.updateAttention() }
    }
    deinit { if let observer = accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer) } }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        shimmer.frame = bounds; outline.frame = bounds
        outline.path = CGPath(roundedRect:bounds.insetBy(dx:1,dy:1),cornerWidth:bounds.height/2,cornerHeight:bounds.height/2,transform:nil)
        CATransaction.commit()
    }
    func updateAttention() {
        guard !isHidden,isEnabled else { stopAttention(); return }
        shimmer.isHidden = false
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            shimmer.removeAllAnimations(); shimmer.locations = [0,0.5,1]; return
        }
        guard shimmer.animation(forKey:"discovery") == nil else { return }
        let animation = CAKeyframeAnimation(keyPath:"locations")
        animation.values = [[-1,-0.5,0],[1,1.5,2],[1,1.5,2]]
        animation.keyTimes = [0,0.65,1]; animation.duration = 3.2
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name:.easeInEaseOut)
        shimmer.add(animation,forKey:"discovery")
    }
    func stopAttention() { shimmer.removeAllAnimations(); shimmer.isHidden = true }
}
