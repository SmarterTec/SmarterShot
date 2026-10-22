import AppKit

/// The capture overlay that pops into the bottom-left corner right after a
/// capture. Shows a thumbnail you can drag out, plus quick actions.
/// Stays until dismissed; multiple overlays stack upward from the corner.
final class OverlayWindow: NSObject, NSTextFieldDelegate {
    private let card: NSView
    private var isDismissing = false
    private var shot: CaptureController.Shot
    private let thumbnail: DraggableImageView
    private let filenameLabel = NSTextField(wrappingLabelWithString: "")
    private let suggestedName = NSTextField(string: "")
    private let descriptionLabel = NSTextField(wrappingLabelWithString: "")
    private let acceptName = NSButton()
    private let analyzer: @MainActor (URL) async throws -> ScreenshotAISuggestion
    private var analysisTask: Task<Void,Never>?
    private static var analysisTail: Task<Void,Never>?
    private static let cornerRadius: CGFloat = 20
    private static let padding: CGFloat = 12
    static let fileRenamed = Notification.Name("SmarterShot.fileRenamed")
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

    init(shot: CaptureController.Shot, analyzeAutomatically: Bool = true, analyzer: @escaping @MainActor (URL) async throws -> ScreenshotAISuggestion = ScreenshotAIService.describe) {
        self.shot = shot
        self.analyzer = analyzer

        let panelWidth: CGFloat = 288
        let pad = Self.padding
        let thumbW = panelWidth
        let img = shot.image
        let aspect = img.size.width > 0 ? img.size.height / img.size.width : 0.66
        let thumbH = min(180, max(96, thumbW * aspect))
        let metadataHeight: CGFloat = 80
        let thumbY = metadataHeight
        let panelHeight = thumbY + thumbH

        let rect = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)

        thumbnail = DraggableImageView(frame:NSRect(x:0,y:thumbY,width:thumbW,height:thumbH))
        let controls = NSView(frame: rect)
        controls.autoresizingMask = [.width,.height]
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame:rect)
            glass.style = .regular
            glass.cornerRadius = Self.cornerRadius
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
            backdrop.layer?.cornerRadius = Self.cornerRadius
            backdrop.layer?.cornerCurve = .continuous
            backdrop.layer?.masksToBounds = true
            backdrop.addSubview(controls)
            card = backdrop
        }
        super.init()
        let effect = controls

        // Thumbnail (draggable out).
        let thumb = thumbnail
        thumb.image = img
        thumb.fileURL = shot.url
        thumb.imageScaling = .scaleProportionallyUpOrDown
        thumb.wantsLayer = true
        thumb.fillsBounds = true
        thumb.layer?.cornerRadius = Self.cornerRadius
        thumb.layer?.maskedCorners = [.layerMinXMaxYCorner,.layerMaxXMaxYCorner]
        thumb.layer?.cornerCurve = .continuous
        thumb.layer?.masksToBounds = true
        thumb.autoresizingMask = [.minYMargin]
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
        for (i, tool) in tools.enumerated() {
            let b = makeToolButton(symbol: tool.0, title: tool.1, action: tool.2)
            b.frame = NSRect(x:8+CGFloat(i)*40,y:panelHeight-8-32,width:32,height:32)
            b.autoresizingMask = [.minYMargin]
            if tool.1 == "Markup" { b.isEnabled = !shot.isVideo }
            effect.addSubview(b)
        }

        // Close ✕ and trash, inset into the thumbnail's top-right corner so the
        // rounded corner doesn't clip them. Aligned on one row with a shadow.
        let iconSize: CGFloat = 32
        let inset: CGFloat = 8
        let cornerY = panelHeight - inset - iconSize
        let closeX = panelWidth - inset - iconSize

        let close = makeCornerButton(symbol: "xmark.circle.fill",
                                     colors: [.white, NSColor.black.withAlphaComponent(0.6)],
                                     action: #selector(closeAction),
                                     tip: "Close (tap again to keep, or tap the trash to delete)")
        close.frame = NSRect(x: closeX, y: cornerY, width: iconSize, height: iconSize)
        close.autoresizingMask = [.minYMargin]
        effect.addSubview(close)

        let deepRed = NSColor(srgbRed: 0.72, green: 0.06, blue: 0.10, alpha: 1.0)
        trashButton = makeCornerButton(symbol: "trash.circle.fill",
                                       colors: [.white, deepRed],
                                       action: #selector(trashAction),
                                       tip: "Delete this screenshot")
        trashButton.frame = NSRect(x: closeX - iconSize - 8, y: cornerY, width: iconSize, height: iconSize)
        trashButton.autoresizingMask = [.minYMargin]
        trashButton.isHidden = true
        effect.addSubview(trashButton)

        filenameLabel.frame = NSRect(x:pad,y:pad+94,width:thumbW,height:32)
        filenameLabel.font = .systemFont(ofSize:12)
        filenameLabel.textColor = .secondaryLabelColor
        filenameLabel.maximumNumberOfLines = 2
        filenameLabel.lineBreakMode = .byWordWrapping
        filenameLabel.isSelectable = true
        filenameLabel.setAccessibilityLabel("Saved filename")
        filenameLabel.stringValue = shot.url.lastPathComponent
        filenameLabel.toolTip = shot.url.lastPathComponent
        effect.addSubview(filenameLabel)
        suggestedName.frame = NSRect(x:pad,y:pad+65,width:thumbW-32,height:24)
        suggestedName.font = .systemFont(ofSize:11)
        suggestedName.placeholderString = "Suggested filename"
        suggestedName.setAccessibilityLabel("Suggested filename, editable")
        suggestedName.isHidden = true
        effect.addSubview(suggestedName)
        acceptName.frame = NSRect(x:panelWidth-pad-28,y:pad+65,width:28,height:24)
        acceptName.image = NSImage(systemSymbolName:"checkmark",accessibilityDescription:"Use suggested filename")
        acceptName.imagePosition = .imageOnly
        acceptName.bezelStyle = .rounded
        acceptName.target = self; acceptName.action = #selector(acceptSuggestedName)
        acceptName.toolTip = "Rename this file using the reviewed name"
        acceptName.setAccessibilityLabel("Use suggested filename")
        acceptName.isHidden = true
        effect.addSubview(acceptName)
        descriptionLabel.frame = NSRect(x:pad,y:pad,width:thumbW,height:57)
        descriptionLabel.font = .systemFont(ofSize:14,weight:.semibold)
        descriptionLabel.textColor = .labelColor
        descriptionLabel.delegate = self
        descriptionLabel.maximumNumberOfLines = 3
        descriptionLabel.isSelectable = true
        descriptionLabel.setAccessibilityLabel("Screenshot description")
        descriptionLabel.stringValue = shot.isVideo ? "Screen recording" : "Description pending"
        effect.addSubview(descriptionLabel)

        layoutMetadata()
        OverlayWindow.document.addSubview(card)
        OverlayWindow.stack.append(self)
        OverlayWindow.restack(animated: false, revealNewest: true)
        card.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            card.animator().alphaValue = 1
        }
        if analyzeAutomatically && !shot.isVideo { startAnalysis() }
    }

    private func layoutMetadata() {
        let width = card.frame.width, pad = Self.padding, textWidth = width-pad*2
        func height(_ field:NSTextField,lines:Int) -> CGFloat {
            let lineHeight = NSLayoutManager().defaultLineHeight(for:field.font!)
            let measured = field.cell!.cellSize(forBounds:NSRect(x:0,y:0,width:textWidth,height:1000)).height
            return ceil(max(lineHeight,min(lineHeight*CGFloat(lines)+2,measured)))
        }
        var y = pad
        if !suggestedName.isHidden {
            suggestedName.frame = NSRect(x:pad,y:y,width:textWidth-32,height:24)
            acceptName.frame = NSRect(x:width-pad-28,y:y,width:28,height:24)
            y += 30
        }
        let bodyHeight = height(filenameLabel,lines:2)
        filenameLabel.frame = NSRect(x:pad,y:y,width:textWidth,height:bodyHeight)
        y += bodyHeight + 6
        let headlineHeight = height(descriptionLabel,lines:3)
        descriptionLabel.frame = NSRect(x:pad,y:y,width:textWidth,height:headlineHeight)
        y += headlineHeight + pad
        let imageHeight = thumbnail.frame.height
        card.setFrameSize(NSSize(width:width,height:y+imageHeight))
        thumbnail.frame = NSRect(x:0,y:y,width:width,height:imageHeight)
        if Self.stack.contains(where: { $0 === self }) { Self.restack(animated:true) }
    }
    func controlTextDidEndEditing(_ notification:Notification) {
        if notification.object as? NSTextField === descriptionLabel { layoutMetadata() }
    }

    private func startAnalysis() {
        // Serialize automatic work so a burst of screenshots doesn't run many
        // local models at once. Waiting never blocks capture, saving or dragging.
        descriptionLabel.stringValue = "Waiting for on-device description…"
        layoutMetadata()
        let previous = Self.analysisTail
        let task = Task { @MainActor [weak self] in
            await previous?.value
            guard !Task.isCancelled,let self = self,!self.isDismissing else { return }
            self.descriptionLabel.stringValue = "Describing on this Mac…"
            self.layoutMetadata()
            do {
                let result = try await self.analyzer(self.shot.url)
                guard !Task.isCancelled,!self.isDismissing else { return }
                self.showSuggestion(result)
            } catch {
                guard !Task.isCancelled,!self.isDismissing else { return }
                self.descriptionLabel.stringValue = error.localizedDescription
                self.descriptionLabel.toolTip = error.localizedDescription
                self.layoutMetadata()
            }
        }
        analysisTask = task; Self.analysisTail = task
    }

    func showSuggestion(_ result: ScreenshotAISuggestion) {
        suggestedName.stringValue = result.suggestedFilename(for:shot.url)
        suggestedName.isHidden = false; acceptName.isHidden = false
        descriptionLabel.stringValue = result.description
        descriptionLabel.toolTip = result.description
        descriptionLabel.isEditable = true
        layoutMetadata()
    }

    @objc private func acceptSuggestedName() {
        do { try useSuggestedFilename() }
        catch {
            let alert = NSAlert(error:error)
            NSApp.activate(ignoringOtherApps:true)
            alert.beginSheetModal(for:Self.host)
        }
    }

    /// Only the explicit checkmark action may move a saved file. Never overwrite
    /// another screenshot, change its image extension, or invalidate an open editor.
    func useSuggestedFilename() throws {
        let name = suggestedName.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty,!name.contains("/"),!name.contains(":"),!name.contains("\n"),
              name.utf8.count <= 240,(name as NSString).pathExtension.lowercased() == shot.url.pathExtension.lowercased(),
              !MarkupWindow.isEditing(url:shot.url) else {
            throw NSError(domain:"SmarterShot",code:1,userInfo:[NSLocalizedDescriptionKey:"Choose a valid filename with the same image extension, and finish open markup before renaming."])
        }
        let original = shot.url
        let destination = original.deletingLastPathComponent().appendingPathComponent(name)
        if destination != original { try FileManager.default.moveItem(at:original,to:destination) }
        for overlay in Self.stack where overlay.shot.url == original {
            overlay.shot = CaptureController.Shot(url:destination,image:overlay.shot.image,isVideo:overlay.shot.isVideo)
            overlay.thumbnail.fileURL = destination
            overlay.filenameLabel.stringValue = name; overlay.filenameLabel.toolTip = name
            overlay.suggestedName.isHidden = true; overlay.acceptName.isHidden = true
            overlay.layoutMetadata()
        }
        NotificationCenter.default.post(name:Self.fileRenamed,object:nil,userInfo:["oldURL":original,"newURL":destination])
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
        b.isBordered = true
        b.imagePosition = .imageOnly
        b.title = ""
        if #available(macOS 26.0, *) { b.bezelStyle = .glass; b.borderShape = .capsule }
        else { b.bezelStyle = .texturedRounded }
        b.setAccessibilityLabel(title)
        b.font = .systemFont(ofSize: 11)
        b.contentTintColor = .labelColor
        b.toolTip = ["Copy":"Copy image to clipboard", "Reveal":"Show screenshot in Finder",
                     "Pin":"Keep image floating above other windows", "Markup":"Edit and annotate screenshot"][title] ?? title
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
        analysisTask?.cancel()
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
        allowsToolTipsWhenApplicationIsInactive = true
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
