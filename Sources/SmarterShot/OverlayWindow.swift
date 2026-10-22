import AppKit

/// The capture overlay that pops into the bottom-left corner right after a
/// capture. Shows a thumbnail you can drag out, plus quick actions.
/// Stays until dismissed; multiple overlays stack upward from the corner.
final class OverlayWindow: NSObject {
    private let card: NSView
    private var isDismissing = false
    private let shot: CaptureController.Shot
    private var trashButton: NSButton!
    private var closeArmed = false
    private var autoDismissTimer: Timer?

    /// All currently visible overlays, oldest first. Index 0 sits at the bottom.
    static var stack: [OverlayWindow] = []

    private static let leftMargin: CGFloat = 20
    private static let bottomMargin: CGFloat = 20
    private static let gap: CGFloat = 10
    private static let host = OverlayStackPanel()
    private static let document = NSView()

    init(shot: CaptureController.Shot) {
        self.shot = shot

        let panelWidth: CGFloat = 288
        let pad: CGFloat = 12
        let thumbW = panelWidth - pad * 2
        let img = shot.image
        let aspect = img.size.width > 0 ? img.size.height / img.size.width : 0.66
        let thumbH = min(180, max(96, thumbW * aspect))
        let toolbarH: CGFloat = 46
        let thumbY = pad + toolbarH + 8
        let panelHeight = thumbY + thumbH + pad

        let rect = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)

        let controls = NSView(frame: rect)
        controls.autoresizingMask = [.width,.height]
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame:rect)
            glass.style = .regular
            glass.cornerRadius = 20
            if #available(macOS 27.0, *) { glass.effectIsInteractive = true }
            // Content must live in contentView so AppKit composites it above glass.
            glass.contentView = controls
            card = glass
        } else {
            let backdrop = NSVisualEffectView(frame:rect)
            backdrop.material = .popover
            backdrop.blendingMode = .behindWindow
            backdrop.state = .active
            backdrop.wantsLayer = true
            backdrop.layer?.cornerRadius = 20
            backdrop.layer?.masksToBounds = true
            backdrop.addSubview(controls)
            card = backdrop
        }
        super.init()
        let effect = controls

        // Thumbnail (draggable out).
        let thumb = DraggableImageView(frame: NSRect(x: pad, y: thumbY, width: thumbW, height: thumbH))
        thumb.image = img
        thumb.fileURL = shot.url
        thumb.imageScaling = .scaleProportionallyUpOrDown
        thumb.wantsLayer = true
        thumb.layer?.cornerRadius = 10
        thumb.layer?.masksToBounds = true
        thumb.layer?.backgroundColor = NSColor(white: 0.5, alpha: 0.15).cgColor
        // Hide the overlay while dragging so only the image moves with the cursor.
        thumb.onDragWillBegin = { [weak self] in self?.card.isHidden = true }
        thumb.onDragEnded = { [weak self] operation in
            guard let self = self else { return }
            if operation.isEmpty {
                self.card.isHidden = false // cancelled — bring the thumbnail back
            } else {
                self.dismiss()       // dropped somewhere — it's been used
            }
        }
        effect.addSubview(thumb)

        // Toolbar: quick actions, including the non-destructive markup editor.
        let tools: [(String, String, Selector)] = [
            ("doc.on.doc", "Copy", #selector(copyAction)),
            ("folder", "Reveal", #selector(revealAction)),
            ("pin", "Pin", #selector(pinAction)),
            ("pencil.tip.crop.circle", "Markup", #selector(markupAction)),
        ]
        let btnW = (panelWidth - pad * 2) / CGFloat(tools.count)
        for (i, tool) in tools.enumerated() {
            let b = makeToolButton(symbol: tool.0, title: tool.1, action: tool.2)
            b.frame = NSRect(x: pad + CGFloat(i) * btnW, y: pad, width: btnW, height: toolbarH - 6)
            if tool.1 == "Markup" { b.isEnabled = !shot.isVideo }
            effect.addSubview(b)
        }

        // Close ✕ and trash, inset into the thumbnail's top-right corner so the
        // rounded corner doesn't clip them. Aligned on one row with a shadow.
        let iconSize: CGFloat = 26
        let inset: CGFloat = 6
        let cornerY = panelHeight - pad - inset - iconSize
        let closeX = panelWidth - pad - inset - iconSize

        let close = makeCornerButton(symbol: "xmark.circle.fill",
                                     colors: [.white, NSColor.black.withAlphaComponent(0.6)],
                                     action: #selector(closeAction),
                                     tip: "Close (tap again to keep, or tap the trash to delete)")
        close.frame = NSRect(x: closeX, y: cornerY, width: iconSize, height: iconSize)
        effect.addSubview(close)

        let deepRed = NSColor(srgbRed: 0.72, green: 0.06, blue: 0.10, alpha: 1.0)
        trashButton = makeCornerButton(symbol: "trash.circle.fill",
                                       colors: [.white, deepRed],
                                       action: #selector(trashAction),
                                       tip: "Delete this screenshot")
        trashButton.frame = NSRect(x: closeX - iconSize - 8, y: cornerY, width: iconSize, height: iconSize)
        trashButton.isHidden = true
        effect.addSubview(trashButton)

        OverlayWindow.document.addSubview(card)
        OverlayWindow.stack.append(self)
        OverlayWindow.restack(animated: false, revealNewest: true)
        card.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            card.animator().alphaValue = 1
        }
    }

    private func makeCornerButton(symbol: String, colors: [NSColor],
                                  action: Selector, tip: String) -> NSButton {
        let b = NSButton()
        b.isBordered = false
        b.bezelStyle = .regularSquare
        b.imageScaling = .scaleProportionallyUpOrDown
        let cfg = NSImage.SymbolConfiguration(pointSize: 24, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: colors))
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
            .withSymbolConfiguration(cfg)
        b.toolTip = tip
        b.target = self
        b.action = action
        b.wantsLayer = true
        b.layer?.shadowColor = NSColor.black.cgColor
        b.layer?.shadowOpacity = 0.35
        b.layer?.shadowRadius = 2.5
        b.layer?.shadowOffset = CGSize(width: 0, height: -1)
        return b
    }

    private func makeToolButton(symbol: String, title: String, action: Selector) -> NSButton {
        let b = NSButton()
        b.isBordered = false
        b.imagePosition = .imageAbove
        b.title = title
        b.font = .systemFont(ofSize: 11)
        b.contentTintColor = .labelColor
        b.toolTip = title
        let cfg = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(cfg)
        b.imageScaling = .scaleProportionallyDown
        b.target = self
        b.action = action
        return b
    }

    /// Re-lay out the whole stack from the bottom-left corner upward.
    private static func restack(animated: Bool, revealNewest: Bool = false) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let oldOffset = host.scroller.contentView.bounds.origin.y
        var y: CGFloat = 0
        for overlay in stack {
            let origin = NSPoint(x:0,y:y)
            if animated { overlay.card.animator().setFrameOrigin(origin) }
            else { overlay.card.setFrameOrigin(origin) }
            y += overlay.card.frame.height + gap
        }
        let height = max(0,y-gap)
        let viewportHeight = min(height,max(1,visible.height-bottomMargin*2))
        host.setFrame(NSRect(x:visible.minX+leftMargin,y:visible.minY+bottomMargin,
                             width:288,height:viewportHeight),display:true)
        document.setFrameSize(NSSize(width:288,height:height))
        if host.scroller.documentView !== document { host.scroller.documentView = document }
        // Finish native clip-view sizing before restoring its offset. Ordering
        // a newly resized panel front can otherwise reset the pending scroll.
        if stack.isEmpty { host.orderOut(nil) } else { host.orderFront(nil) }
        host.scroller.tile()
        host.scroller.layoutSubtreeIfNeeded()
        let maximumOffset = max(0,height-host.scroller.contentView.bounds.height)
        let offset = revealNewest ? maximumOffset : min(maximumOffset,max(0,oldOffset))
        host.scroller.contentView.scroll(to:NSPoint(x:0,y:offset))
        host.scroller.reflectScrolledClipView(host.scroller.contentView)
    }

    fileprivate static func relayoutForScreenChange() { restack(animated:false) }

    /// Dismiss this overlay `seconds` from now (used after the user pastes the
    /// screenshot). The saved file is not affected.
    func scheduleAutoDismiss(after seconds: TimeInterval) {
        autoDismissTimer?.invalidate()
        autoDismissTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true
        autoDismissTimer?.invalidate()
        PasteWatcher.shared.forget(self)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            card.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            self.card.removeFromSuperview()
            OverlayWindow.stack.removeAll { $0 === self }
            OverlayWindow.restack(animated: true)
        })
    }

    @objc private func copyAction() {
        CaptureController.copyToClipboard(shot)
        PasteWatcher.shared.noteCopied(overlay: self) // this shot is now the paste target
        // brief pulse to confirm.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.08
            card.animator().alphaValue = 0.6
        } completionHandler: {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.08
                self.card.animator().alphaValue = 1.0
            }
        }
    }

    @objc private func markupAction() {
        autoDismissTimer?.invalidate()
        PasteWatcher.shared.forget(self)
        _ = MarkupWindow(shot: shot) { edited in
            // Replacing a screenshot must retire thumbnails holding its old pixels.
            for overlay in OverlayWindow.stack where overlay.shot.url == edited.url { overlay.dismiss() }
            CaptureController.copyToClipboard(edited)
            let overlay = OverlayWindow(shot: edited)
            PasteWatcher.shared.noteCopied(overlay: overlay)
        }
    }

    @objc private func revealAction() {
        NSWorkspace.shared.activateFileViewerSelecting([shot.url])
    }

    @objc private func pinAction() {
        let rect = Self.host.convertToScreen(card.convert(card.bounds,to:nil))
        let topLeft = NSPoint(x:rect.midX-100,y:rect.maxY+40)
        _ = PinnedWindow(image: shot.image, at: topLeft)
        dismiss()
    }

    @objc private func closeAction() {
        // First tap arms: reveal the red trash. Second tap keeps & closes.
        if !closeArmed {
            closeArmed = true
            trashButton.isHidden = false
            trashButton.alphaValue = 0
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                trashButton.animator().alphaValue = 1
            }
        } else {
            dismiss() // keep the file
        }
    }

    @objc private func trashAction() {
        CaptureController.delete(shot)
        dismiss()
    }
}

/// A single clipped viewport keeps every thumbnail reachable without placing
/// windows beyond the display. Native scrolling works without visible scrollers.
private final class OverlayStackPanel: NSPanel {
    let scroller = NSScrollView()
    init() {
        super.init(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        title = "Screenshot Previews"
        isFloatingPanel = true; level = .statusBar
        collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
        backgroundColor = .clear; isOpaque = false; hasShadow = false
        scroller.drawsBackground = false
        scroller.hasVerticalScroller = false; scroller.hasHorizontalScroller = false
        scroller.verticalScrollElasticity = .none; scroller.horizontalScrollElasticity = .none
        contentView = scroller
        NotificationCenter.default.addObserver(self,selector:#selector(screenChanged),
            name:NSApplication.didChangeScreenParametersNotification,object:nil)
    }
    override var canBecomeKey: Bool { true }
    @objc private func screenChanged() { OverlayWindow.relayoutForScreenChange() }
}
