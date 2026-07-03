import AppKit

/// A borderless, always-on-top window that "pins" a screenshot to the screen.
/// - Drag anywhere to move.
/// - Scroll (or pinch) to resize.
/// - +/- keys resize, [ ] adjust opacity.
/// - Esc or the hover close button removes it.
final class PinnedWindow: NSPanel {
    private let imageView = NSImageView()
    private let closeButton = NSButton()
    private let baseAspect: CGFloat
    private let nativeSize: NSSize

    static var openWindows: [PinnedWindow] = []

    init(image: NSImage, at topLeft: NSPoint) {
        nativeSize = image.size == .zero ? NSSize(width: 400, height: 300) : image.size
        baseAspect = nativeSize.height / max(nativeSize.width, 1)

        // Start at a comfortable size, capped so huge shots don't fill the screen.
        let startWidth = min(nativeSize.width, 500)
        let startHeight = startWidth * baseAspect
        let rect = NSRect(x: topLeft.x, y: topLeft.y - startHeight,
                          width: startWidth, height: startHeight)

        super.init(contentRect: rect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        backgroundColor = .clear
        hasShadow = true
        isOpaque = false

        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.frame = NSRect(origin: .zero, size: rect.size)
        imageView.autoresizingMask = [.width, .height]
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 6
        imageView.layer?.masksToBounds = true

        let content = PinnedContentView(frame: NSRect(origin: .zero, size: rect.size))
        content.owner = self
        content.addSubview(imageView)

        // Hover close button (top-left), hidden until mouse enters.
        closeButton.frame = NSRect(x: 6, y: rect.height - 26, width: 20, height: 20)
        closeButton.bezelStyle = .circular
        closeButton.title = "✕"
        closeButton.isBordered = true
        closeButton.autoresizingMask = [.minYMargin]
        closeButton.target = self
        closeButton.action = #selector(closePinned)
        closeButton.isHidden = true
        content.addSubview(closeButton)

        contentView = content
        makeKeyAndOrderFront(nil)

        PinnedWindow.openWindows.append(self)
    }

    override var canBecomeKey: Bool { true }

    func setHoverControlsVisible(_ visible: Bool) {
        closeButton.isHidden = !visible
    }

    @objc private func closePinned() {
        PinnedWindow.openWindows.removeAll { $0 === self }
        orderOut(nil)
        close()
    }

    private func resize(by factor: CGFloat) {
        var f = frame
        let newWidth = max(80, min(nativeSize.width * 2, f.width * factor))
        let newHeight = newWidth * baseAspect
        // Keep top-left anchored while resizing.
        f.origin.y += (f.height - newHeight)
        f.size = NSSize(width: newWidth, height: newHeight)
        setFrame(f, display: true, animate: false)
    }

    private func adjustOpacity(by delta: CGFloat) {
        alphaValue = max(0.2, min(1.0, alphaValue + delta))
    }

    override func scrollWheel(with event: NSEvent) {
        let factor = 1.0 + (event.scrollingDeltaY * 0.005)
        resize(by: factor)
    }

    override func keyDown(with event: NSEvent) {
        switch event.charactersIgnoringModifiers {
        case "\u{1b}": closePinned()          // Esc
        case "=", "+": resize(by: 1.1)
        case "-", "_": resize(by: 0.9)
        case "]": adjustOpacity(by: 0.1)
        case "[": adjustOpacity(by: -0.1)
        default: super.keyDown(with: event)
        }
    }
}

/// Content view that surfaces mouse-enter/exit to toggle the close button.
private final class PinnedContentView: NSView {
    weak var owner: PinnedWindow?
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking = tracking { removeTrackingArea(tracking) }
        let ta = NSTrackingArea(rect: bounds,
                                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                owner: self, userInfo: nil)
        addTrackingArea(ta)
        tracking = ta
    }
    override func mouseEntered(with event: NSEvent) { owner?.setHoverControlsVisible(true) }
    override func mouseExited(with event: NSEvent) { owner?.setHoverControlsVisible(false) }
}
