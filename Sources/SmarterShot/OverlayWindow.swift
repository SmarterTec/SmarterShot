import AppKit

/// The capture overlay that pops into the bottom-left corner right after a
/// capture. Shows a thumbnail you can drag out, plus quick actions.
/// Stays until dismissed; multiple overlays stack upward from the corner.
final class OverlayWindow: NSPanel {
    private let shot: CaptureController.Shot
    private var trashButton: NSButton!
    private var closeArmed = false

    /// All currently visible overlays, oldest first. Index 0 sits at the bottom.
    static var stack: [OverlayWindow] = []

    private static let leftMargin: CGFloat = 20
    private static let bottomMargin: CGFloat = 20
    private static let gap: CGFloat = 10
    /// Cap how many overlays can pile up; the oldest is dropped past this.
    private static let maxStack = 6

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

        super.init(contentRect: rect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        appearance = nil // follow the system light/dark appearance

        // Translucent, appearance-adaptive background.
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: rect.size))
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 1
        effect.layer?.borderColor = NSColor.separatorColor.cgColor

        // Thumbnail (draggable out).
        let thumb = DraggableImageView(frame: NSRect(x: pad, y: thumbY, width: thumbW, height: thumbH))
        thumb.image = img
        thumb.fileURL = shot.url
        thumb.imageScaling = .scaleProportionallyUpOrDown
        thumb.wantsLayer = true
        thumb.layer?.cornerRadius = 6
        thumb.layer?.masksToBounds = true
        thumb.layer?.backgroundColor = NSColor(white: 0.5, alpha: 0.15).cgColor
        // Hide the overlay while dragging so only the image moves with the cursor.
        thumb.onDragWillBegin = { [weak self] in self?.orderOut(nil) }
        thumb.onDragEnded = { [weak self] operation in
            guard let self = self else { return }
            if operation.isEmpty {
                self.orderFront(nil) // cancelled — bring the overlay back
            } else {
                self.dismiss()       // dropped somewhere — it's been used
            }
        }
        effect.addSubview(thumb)

        // Toolbar: three roomy icon buttons.
        let tools: [(String, String, Selector)] = [
            ("doc.on.doc", "Copy", #selector(copyAction)),
            ("folder", "Reveal", #selector(revealAction)),
            ("pin", "Pin", #selector(pinAction)),
        ]
        let btnW = (panelWidth - pad * 2) / CGFloat(tools.count)
        for (i, tool) in tools.enumerated() {
            let b = makeToolButton(symbol: tool.0, title: tool.1, action: tool.2)
            b.frame = NSRect(x: pad + CGFloat(i) * btnW, y: pad, width: btnW, height: toolbarH - 6)
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

        contentView = effect

        OverlayWindow.stack.append(self)
        // Drop the oldest overlays if we exceed the cap. Remove synchronously
        // (not via the animated dismiss) so the stack count updates immediately.
        while OverlayWindow.stack.count > OverlayWindow.maxStack {
            let oldest = OverlayWindow.stack.removeFirst()
            oldest.orderOut(nil)
        }
        OverlayWindow.restack(animated: false)

        alphaValue = 0
        orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            animator().alphaValue = 1
        }
    }

    override var canBecomeKey: Bool { true }

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
    private static func restack(animated: Bool) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        var y = visible.minY + bottomMargin
        let x = visible.minX + leftMargin
        for win in stack {
            let origin = NSPoint(x: x, y: y)
            if animated {
                win.animator().setFrameOrigin(origin)
            } else {
                win.setFrameOrigin(origin)
            }
            y += win.frame.height + gap
        }
    }

    func dismiss() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            self.orderOut(nil)
            OverlayWindow.stack.removeAll { $0 === self }
            OverlayWindow.restack(animated: true)
        })
    }

    @objc private func copyAction() {
        CaptureController.copyToClipboard(shot)
        // brief pulse to confirm.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.08
            animator().alphaValue = 0.6
        } completionHandler: {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.08
                self.animator().alphaValue = 1.0
            }
        }
    }

    @objc private func revealAction() {
        NSWorkspace.shared.activateFileViewerSelecting([shot.url])
    }

    @objc private func pinAction() {
        let topLeft = NSPoint(x: frame.midX - 100, y: frame.maxY + 40)
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
