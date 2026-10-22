import AppKit

/// A non-destructive screenshot editor. Coordinates are image points; export
/// uses the source bitmap's pixel dimensions rather than the window resolution.
final class MarkupWindow: NSWindowController, NSWindowDelegate, NSComboBoxDelegate {
    private static var editors: [MarkupWindow] = []
    private let canvas: MarkupCanvas
    private let source: URL
    private let onSave: (CaptureController.Shot) -> Void
    private let status = NSTextField(labelWithString: "Drag to draw. Select to move shapes or drag their handles. Use Edit Points to adjust handles or double-click an outline to add a point.")

    init(shot: CaptureController.Shot, onSave: @escaping (CaptureController.Shot) -> Void) {
        source = shot.url
        self.onSave = onSave
        canvas = MarkupCanvas(image: shot.image)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 780),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Markup — \(shot.url.lastPathComponent)"
        window.minSize = NSSize(width: 850, height: 500)
        window.delegate = self
        window.isReleasedWhenClosed = false
        let root = NSView()
        window.contentView = root
        let tools = NSStackView()
        tools.orientation = .horizontal
        tools.spacing = 4
        var toolButtons: [NSButton] = []
        for (index, tool) in MarkupCanvas.Tool.allCases.enumerated() {
            let button = NSButton(title: tool.rawValue, target: self, action: #selector(selectTool(_:)))
            button.tag = index
            button.bezelStyle = .texturedRounded
            button.setButtonType(.pushOnPushOff)
            button.state = tool == canvas.tool ? .on : .off
            button.setAccessibilityLabel(tool.rawValue)
            tools.addArrangedSubview(button)
            toolButtons.append(button)
        }
        canvas.onToolChanged = { [weak canvas, weak status, toolButtons] in
            guard let canvas = canvas else { return }
            // Only drawing-tool buttons participate: NSPopUpButton is also an
            // NSButton, but its default tag is not a drawing-tool index.
            for (index, button) in toolButtons.enumerated() {
                button.state = MarkupCanvas.Tool.allCases[index] == canvas.tool ? .on : .off
            }
            status?.stringValue = canvas.tool == .select
                ? "Select · Drag to move. Drag the text corner to resize. Double-click text to edit; use Edit Points for shape handles."
                : canvas.tool == .text
                    ? "Text · Click the image and type. Press Return to finish, then drag to move."
                    : "\(canvas.tool.rawValue) · Drag to draw. Use Edit Points for handles, then double-click an outline to add a point."
        }
        let color = NSColorWell()
        color.color = .systemBlue
        color.target = self
        color.action = #selector(changeColor(_:))
        color.setAccessibilityLabel("Stroke color")
        color.widthAnchor.constraint(equalToConstant: 36).isActive = true
        tools.addArrangedSubview(color)
        let width = NSPopUpButton()
        width.addItems(withTitles: ["Thin", "Medium", "Thick"])
        width.selectItem(at: 1)
        width.target = self
        width.action = #selector(changeWidth(_:))
        width.setAccessibilityLabel("Line width")
        tools.addArrangedSubview(width)
        let editPoints = NSButton(title: "Edit Points", target: self, action: #selector(togglePointEditing))
        editPoints.bezelStyle = .rounded
        editPoints.setButtonType(.toggle)
        editPoints.isEnabled = false
        canvas.onEditingChanged = { [weak canvas, weak editPoints] in
            editPoints?.isEnabled = canvas?.canEditPoints ?? false
            editPoints?.state = canvas?.isEditingPoints == true ? .on : .off
        }
        let textTools = NSStackView()
        textTools.spacing = 8
        textTools.addArrangedSubview(NSTextField(labelWithString: "Font"))
        let font = NSPopUpButton()
        font.addItems(withTitles: ["System"] + NSFontManager.shared.availableFontFamilies.sorted())
        font.target = self
        font.action = #selector(changeFontFamily(_:))
        font.setAccessibilityLabel("Text font")
        font.widthAnchor.constraint(equalToConstant: 210).isActive = true
        textTools.addArrangedSubview(font)
        textTools.addArrangedSubview(NSTextField(labelWithString: "Size"))
        let size = NSComboBox()
        size.addItems(withObjectValues: [12, 16, 18, 24, 32, 48, 64, 96].map(String.init))
        size.stringValue = "24"
        size.target = self
        size.action = #selector(changeTextSize(_:))
        size.delegate = self
        size.setAccessibilityLabel("Text size")
        size.widthAnchor.constraint(equalToConstant: 72).isActive = true
        textTools.addArrangedSubview(size)
        textTools.addArrangedSubview(NSTextField(labelWithString: "Use the color picker above for text color."))
        let previousCallback = canvas.onEditingChanged
        canvas.onEditingChanged = { [weak canvas, weak font, weak size, weak color] in
            previousCallback?()
            guard let canvas = canvas else { return }
            font?.selectItem(withTitle: canvas.selectedTextFamily)
            size?.stringValue = String(Int(canvas.selectedTextSize.rounded()))
            if let ink = canvas.selectedColor { color?.color = ink }
        }
        let actions = NSStackView()
        actions.spacing = 8
        actions.addArrangedSubview(editPoints)
        for (title, selector) in [("Undo", #selector(undoEdit)), ("Redo", #selector(redoEdit)),
                                  ("Delete", #selector(deleteEdit)), ("Copy", #selector(copyImage)),
                                  ("Cancel", #selector(cancel)), ("Save Copy", #selector(save))] {
            let button = NSButton(title: title, target: self, action: selector)
            button.bezelStyle = .rounded
            actions.addArrangedSubview(button)
        }
        let scroll = NSScrollView()
        scroll.contentView = MarkupClipView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.allowsMagnification = true
        scroll.minMagnification = 0.1
        scroll.maxMagnification = 4
        scroll.documentView = canvas
        scroll.backgroundColor = .underPageBackgroundColor
        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        for view in [tools, textTools, scroll, status, actions] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            tools.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            tools.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            textTools.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            textTools.topAnchor.constraint(equalTo: tools.bottomAnchor, constant: 8),
            scroll.topAnchor.constraint(equalTo: textTools.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -10),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            status.bottomAnchor.constraint(equalTo: actions.topAnchor, constant: -10),
            actions.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            actions.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12)
        ])
        window.center()
        Self.editors.append(self)
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
        root.layoutSubtreeIfNeeded()
        canvas.fitInViewport()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }
    func windowWillClose(_ notification: Notification) { Self.editors.removeAll { $0 === self } }
    @objc private func selectTool(_ sender: NSButton) {
        guard MarkupCanvas.Tool.allCases.indices.contains(sender.tag) else { return }
        canvas.tool = MarkupCanvas.Tool.allCases[sender.tag]
        window?.makeFirstResponder(canvas)
    }
    @objc private func changeColor(_ sender: NSColorWell) { canvas.ink = sender.color; canvas.restyleSelection() }
    @objc private func changeWidth(_ sender: NSPopUpButton) { canvas.strokeWidth = [2.0, 5.0, 10.0][sender.indexOfSelectedItem]; canvas.restyleSelection() }
    @objc private func changeFontFamily(_ sender: NSPopUpButton) {
        canvas.setTextFamily(sender.titleOfSelectedItem ?? "System")
    }
    @objc private func changeTextSize(_ sender: NSComboBox) {
        if let value = Double(sender.stringValue), value.isFinite { canvas.setTextSize(CGFloat(value)) }
    }
    func controlTextDidEndEditing(_ notification: Notification) {
        if let sender = notification.object as? NSComboBox { changeTextSize(sender) }
    }
    func comboBoxSelectionDidChange(_ notification: Notification) {
        guard let sender = notification.object as? NSComboBox,
              let value = sender.objectValueOfSelectedItem as? String, let size = Double(value) else { return }
        canvas.setTextSize(CGFloat(size))
    }
    @objc private func togglePointEditing() { canvas.togglePointEditing(); window?.makeFirstResponder(canvas) }
    @objc private func undoEdit() { canvas.undoEdit() }
    @objc private func redoEdit() { canvas.redoEdit() }
    @objc private func deleteEdit() { canvas.deleteSelection() }
    @objc private func cancel() { close() }
    @objc private func copyImage() {
        guard let image = canvas.render() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        status.stringValue = "Annotated image copied."
    }
    @objc private func save() {
        guard let image = canvas.render(), let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { return }
        let stem = source.deletingPathExtension().lastPathComponent + " — Markup"
        var destination = source.deletingLastPathComponent().appendingPathComponent(stem + ".png")
        var suffix = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = source.deletingLastPathComponent().appendingPathComponent("\(stem) (\(suffix)).png")
            suffix += 1
        }
        do {
            try png.write(to: destination, options: .atomic)
            onSave(CaptureController.Shot(url: destination, image: image))
            close()
        } catch {
            let alert = NSAlert(error: error)
            alert.beginSheetModal(for: window!)
        }
    }
}

final class MarkupCanvas: NSView, NSTextFieldDelegate {
    enum Tool: String, CaseIterable { case select = "Select", sketch = "Sketch", curve = "Curve", line = "Line", arrow = "Arrow", rectangle = "Box", ellipse = "Oval", text = "Text", highlight = "Highlight", crop = "Crop" }
    struct Mark {
        var tool: Tool
        var points: [NSPoint]
        var color: NSColor
        var width: CGFloat
        var text = ""
        var fontFamily = "System"
        var fontSize: CGFloat = 24
    }
    let image: NSImage
    var onToolChanged: (() -> Void)?
    var tool: Tool = .curve { didSet { onToolChanged?() } }
    var ink: NSColor = .systemBlue
    var strokeWidth: CGFloat = 5
    private var textFamily = "System"
    private var textSize: CGFloat = 24
    private var textEditor: NSTextField?
    private var editingTextIndex: Int?
    private var textResizeRect = NSRect.zero
    private var textResizeSize: CGFloat = 24
    private var marks: [Mark] = []
    var selectedTextFamily: String { selected.map { marks[$0].fontFamily } ?? textFamily }
    var selectedTextSize: CGFloat { selected.map { marks[$0].fontSize } ?? textSize }
    var selectedColor: NSColor? { selected.map { marks[$0].color } }
    private func font(for mark: Mark) -> NSFont {
        if mark.fontFamily == "System" { return NSFont.systemFont(ofSize: mark.fontSize) }
        return NSFontManager.shared.font(withFamily:mark.fontFamily,traits:[],weight:5,size:mark.fontSize)
            ?? NSFont.systemFont(ofSize:mark.fontSize)
    }
    private func textRect(_ mark: Mark) -> NSRect {
        let size = (mark.text as NSString).size(withAttributes:[.font:font(for:mark)])
        return NSRect(origin:mark.points[0],size:NSSize(width:max(12,size.width),height:size.height))
    }
    func setTextFamily(_ family: String) {
        textFamily = family
        if let i = selected, marks[i].tool == .text { checkpoint(); marks[i].fontFamily = family; refreshTextEditor(); needsDisplay = true }
    }
    func setTextSize(_ size: CGFloat) {
        textSize = max(6,min(300,size))
        if let i = selected, marks[i].tool == .text { checkpoint(); marks[i].fontSize = textSize; refreshTextEditor(); needsDisplay = true }
    }
    private func beginTextEditing(at i: Int) {
        finishTextEditing()
        editingTextIndex = i
        let field = NSTextField(string:marks[i].text)
        field.font = font(for:marks[i])
        field.textColor = marks[i].color
        field.isBordered = false
        field.drawsBackground = true
        field.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.9)
        field.delegate = self
        field.focusRingType = .exterior
        field.setAccessibilityLabel("Edit annotation text")
        textEditor = field
        addSubview(field)
        refreshTextEditor()
        field.selectText(nil)
    }
    private func refreshTextEditor() {
        guard let i = editingTextIndex, let field = textEditor else { return }
        field.font = font(for:marks[i]); field.textColor = marks[i].color
        let rect = textRect(marks[i])
        field.frame = NSRect(x:rect.minX,y:rect.minY,width:max(140,rect.width+12),height:rect.height+4)
    }
    private func finishTextEditing() {
        guard let i = editingTextIndex, let field = textEditor else { return }
        marks[i].text = field.stringValue
        editingTextIndex = nil; textEditor = nil
        field.delegate = nil
        field.removeFromSuperview()
        needsDisplay = true
    }
    func controlTextDidChange(_ notification: Notification) {
        guard let i = editingTextIndex, let field = textEditor else { return }
        marks[i].text = field.stringValue; refreshTextEditor(); needsDisplay = true
    }
    func controlTextDidEndEditing(_ notification: Notification) { finishTextEditing() }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) || selector == #selector(NSResponder.cancelOperation(_:)) {
            finishTextEditing(); window?.makeFirstResponder(self); return true
        }
        return false
    }
    private var history: [[Mark]] = []
    private var future: [[Mark]] = []
    var onEditingChanged: (() -> Void)?
    private(set) var isEditingPoints = false { didSet { onEditingChanged?(); needsDisplay = true } }
    var canEditPoints: Bool {
        guard let i = selected else { return false }
        return ![Tool.text, .crop, .highlight].contains(marks[i].tool)
    }
    private var selected: Int? { didSet { onEditingChanged?() } }
    func togglePointEditing() {
        guard canEditPoints, let i = selected else { return }
        if !isEditingPoints { prepareOutline(at: i) }
        isEditingPoints.toggle()
    }
    private func prepareOutline(at i: Int) {
        guard marks[i].points.count == 2 else { return }
        let r = rect(marks[i])
        if marks[i].tool == .rectangle {
            checkpoint()
            marks[i].points = [r.origin, NSPoint(x:r.maxX,y:r.minY), NSPoint(x:r.maxX,y:r.maxY), NSPoint(x:r.minX,y:r.maxY)]
        } else if marks[i].tool == .ellipse {
            checkpoint()
            marks[i].points = (0..<8).map { index in
                let angle = CGFloat(index) * .pi / 4
                return NSPoint(x:r.midX + r.width/2*cos(angle), y:r.midY + r.height/2*sin(angle))
            }
        }
    }
    private var handle: Int?
    private var lastPoint = NSPoint.zero
    private var drawing = false
    private var exporting = false
    private var cropAnimation: Timer?
    private var isAnimatingCrop = false
    private var imageBounds: NSRect { NSRect(origin: .zero, size: image.size) }
    private var committedCrop: NSRect {
        guard let crop = marks.last(where: { $0.tool == .crop }) else { return imageBounds }
        let area = rect(crop).intersection(imageBounds)
        return area.width >= 1 && area.height >= 1 ? area : imageBounds
    }

    func fitInViewport() {
        guard let scroll = enclosingScrollView else { return }
        let viewport = scroll.contentView.frame.size
        scroll.magnification = max(scroll.minMagnification, min(scroll.maxMagnification,
            min(1, min((viewport.width - 48) / bounds.width, (viewport.height - 48) / bounds.height))))
        centerInViewport()
    }

    private func centerInViewport() {
        guard let scroll = enclosingScrollView else { return }
        let viewport = scroll.contentView.bounds.size
        scroll.contentView.scroll(to: NSPoint(x: (frame.width - viewport.width) / 2,
                                              y: (frame.height - viewport.height) / 2))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    private func showCommittedCrop(animated: Bool = true) {
        cropAnimation?.invalidate()
        cropAnimation = nil
        let target = committedCrop
        let start = bounds
        let scroll = enclosingScrollView
        let startZoom = scroll?.magnification ?? 1
        let viewport = scroll?.contentView.frame.size ?? target.size
        let targetZoom = max(scroll?.minMagnification ?? 0.1, min(scroll?.maxMagnification ?? 4,
            min((viewport.width - 48) / target.width, (viewport.height - 48) / target.height)))
        let apply: (CGFloat) -> Void = { [weak self] progress in
            guard let self = self else { return }
            let area = NSRect(x: start.minX + (target.minX - start.minX) * progress,
                              y: start.minY + (target.minY - start.minY) * progress,
                              width: start.width + (target.width - start.width) * progress,
                              height: start.height + (target.height - start.height) * progress)
            self.setFrameSize(area.size)
            self.bounds = area
            if let scroll = scroll { scroll.magnification = startZoom + (targetZoom - startZoom) * progress }
            self.centerInViewport()
            self.needsDisplay = true
        }
        guard animated, scroll != nil, !NSEqualRects(start, target),
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            isAnimatingCrop = false
            apply(1)
            return
        }
        isAnimatingCrop = true
        let began = Date.timeIntervalSinceReferenceDate
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            let t = min(1, (Date.timeIntervalSinceReferenceDate - began) / 0.28)
            apply(CGFloat(t * t * (3 - 2 * t)))
            if t >= 1 {
                timer.invalidate()
                self?.cropAnimation = nil
                self?.isAnimatingCrop = false
            }
        }
        cropAnimation = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    override var acceptsFirstResponder: Bool { true }
    init(image: NSImage) {
        self.image = image
        super.init(frame: NSRect(origin: .zero, size: image.size))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }
    private func checkpoint() { history.append(marks); future.removeAll() }
    func undoEdit() { finishTextEditing(); guard let previous = history.popLast() else { return }; future.append(marks); marks = previous; selected = nil; showCommittedCrop(); needsDisplay = true }
    func redoEdit() { finishTextEditing(); guard let next = future.popLast() else { return }; history.append(marks); marks = next; selected = nil; showCommittedCrop(); needsDisplay = true }
    func deleteSelection() { finishTextEditing(); guard let i = selected else { return }; checkpoint(); marks.remove(at: i); selected = nil; showCommittedCrop(); needsDisplay = true }
    func restyleSelection() { guard let i = selected else { return }; checkpoint(); marks[i].color = ink; marks[i].width = strokeWidth; refreshTextEditor(); needsDisplay = true }
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "z" {
            if event.modifierFlags.contains(.shift) { redoEdit() } else { undoEdit() }; return
        }
        if event.keyCode == 51 || event.keyCode == 117 { deleteSelection(); return }
        super.keyDown(with: event)
    }
    private func distance(_ a: NSPoint, _ b: NSPoint) -> CGFloat { hypot(a.x-b.x, a.y-b.y) }
    private var hitRadius: CGFloat { 10 / max(0.1, (enclosingScrollView?.magnification ?? 1)) }
    private func rect(_ mark: Mark) -> NSRect {
        let a = mark.points.first!, b = mark.points.last!
        return NSRect(x: min(a.x,b.x), y: min(a.y,b.y), width: abs(a.x-b.x), height: abs(a.y-b.y))
    }
    private func path(_ mark: Mark) -> NSBezierPath {
        let p = NSBezierPath()
        p.lineWidth = mark.width
        p.lineCapStyle = .round
        p.lineJoinStyle = .round
        let points = mark.points
        if mark.tool == .highlight || mark.tool == .crop || (mark.tool == .rectangle && points.count == 2) { p.appendRect(rect(mark)); return p }
        if mark.tool == .ellipse && points.count == 2 { p.appendOval(in: rect(mark)); return p }
        let closed = mark.tool == .rectangle || mark.tool == .ellipse
        p.move(to: points[0])
        if mark.tool == .curve || mark.tool == .sketch || mark.tool == .ellipse {
            // Closed outlines wrap their neighboring points at the seam.
            for i in 0..<(closed ? points.count : points.count-1) {
                let a = points[closed ? (i-1+points.count)%points.count : max(0,i-1)]
                let b = points[i], c = points[(i+1)%points.count]
                let d = points[closed ? (i+2)%points.count : min(points.count-1,i+2)]
                p.curve(to: c, controlPoint1: NSPoint(x:b.x+(c.x-a.x)/6, y:b.y+(c.y-a.y)/6),
                        controlPoint2: NSPoint(x:c.x-(d.x-b.x)/6, y:c.y-(d.y-b.y)/6))
            }
        } else { for point in points.dropFirst() { p.line(to: point) } }
        if closed { p.close() }
        if mark.tool == .arrow, let end = points.last {
            let start = points[0], angle = atan2(end.y-start.y,end.x-start.x), length = max(15,mark.width*4)
            for offset in [-CGFloat.pi/6, CGFloat.pi/6] {
                p.move(to: end)
                p.line(to: NSPoint(x:end.x-length*cos(angle+offset), y:end.y-length*sin(angle+offset)))
            }
        }
        return p
    }
    override func draw(_ dirtyRect: NSRect) {
        // Explicit clipping is needed with newer AppKit defaults: the source
        // image extends beyond the document bounds after a non-destructive crop.
        if !exporting { NSBezierPath(rect: bounds).addClip() }
        image.draw(in: imageBounds)
        for mark in marks {
            if mark.tool == .crop {
                if !exporting && drawing {
                    let mask = NSBezierPath(rect: bounds)
                    mask.appendRect(rect(mark))
                    mask.windingRule = .evenOdd
                    NSColor.black.withAlphaComponent(0.4).setFill()
                    mask.fill()
                    NSColor.white.setStroke()
                    let border = path(mark)
                    border.lineWidth = 1 / (enclosingScrollView?.magnification ?? 1)
                    border.stroke()
                }
                continue
            }
            mark.color.setStroke()
            if mark.tool == .text {
                (mark.text as NSString).draw(at: mark.points[0], withAttributes: [.foregroundColor: mark.color, .font: font(for: mark)])
            } else if mark.tool == .highlight {
                mark.color.withAlphaComponent(0.3).setFill(); path(mark).fill()
            } else { path(mark).stroke() }
        }
        if !exporting, let i = selected, marks[i].tool == .text, editingTextIndex == nil {
            let r = textRect(marks[i])
            NSColor.systemBlue.setStroke()
            let border = NSBezierPath(rect:r.insetBy(dx:-3,dy:-3))
            border.lineWidth = hitRadius/10
            border.stroke()
            NSColor.systemBlue.setFill()
            NSBezierPath(rect:NSRect(x:r.maxX-hitRadius/2,y:r.maxY-hitRadius/2,width:hitRadius,height:hitRadius)).fill()
        }
        if !exporting, isEditingPoints, let i = selected {
            for (j, point) in marks[i].points.enumerated() {
                let radius = hitRadius * 0.45
                let dot = NSBezierPath(ovalIn: NSRect(x:point.x-radius,y:point.y-radius,width:radius*2,height:radius*2))
                (j == 0 || j == marks[i].points.count-1 ? NSColor.systemBlue : NSColor.systemGreen).setFill()
                dot.fill(); NSColor.white.setStroke(); dot.lineWidth = radius/4; dot.stroke()
            }
        }
    }
    override func mouseDown(with event: NSEvent) {
        guard !isAnimatingCrop else { return }
        finishTextEditing()
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        lastPoint = point; drawing = false; handle = nil
        if tool == .select {
            if let i = selected {
                if marks[i].tool == .text {
                    let r = textRect(marks[i])
                    if event.clickCount == 2 && r.contains(point) { checkpoint(); beginTextEditing(at:i); return }
                    if distance(point,NSPoint(x:r.maxX,y:r.maxY)) < hitRadius {
                        checkpoint(); handle = -1; textResizeRect = r; textResizeSize = marks[i].fontSize; return
                    }
                }
                if event.clickCount == 2, [.curve, .sketch, .rectangle, .ellipse].contains(marks[i].tool) {
                    prepareOutline(at: i)
                    isEditingPoints = true
                    checkpoint()
                    let pts = marks[i].points
                    let closed = marks[i].tool == .rectangle || marks[i].tool == .ellipse
                    let segment = (0..<(closed ? pts.count : pts.count-1)).min {
                        segmentDistance(point,pts[$0],pts[($0+1)%pts.count]) < segmentDistance(point,pts[$1],pts[($1+1)%pts.count])
                    }!
                    marks[i].points.insert(point, at: segment+1)
                    handle = segment+1; needsDisplay = true; return
                }
                if isEditingPoints, let j = marks[i].points.indices.first(where: { distance(point, marks[i].points[$0]) < hitRadius }) {
                    checkpoint(); handle = j; return
                }
            }
            selected = marks.indices.reversed().first { i in
                let m = marks[i]
                if m.tool == .crop { return false }
                if m.tool == .text {
                    return textRect(m).insetBy(dx:-hitRadius,dy:-hitRadius).contains(point)
                }
                if m.tool == .highlight { return rect(m).contains(point) }
                let cg = path(m).cgPathForHitTesting
                return cg.copy(strokingWithWidth: max(m.width,hitRadius*2),lineCap:.round,lineJoin:.round,miterLimit:10).contains(point)
            }
            isEditingPoints = selected.map { marks[$0].tool == .curve } ?? false
            if selected != nil { checkpoint() }
        } else if tool == .text {
            checkpoint()
            var mark = Mark(tool:.text,points:[point],color:ink,width:strokeWidth,text:"Text")
            mark.fontFamily = textFamily; mark.fontSize = textSize
            marks.append(mark)
            selected = marks.count-1
            isEditingPoints = false
            tool = .select
            beginTextEditing(at:marks.count-1)
        } else {
            checkpoint()
            if tool == .crop { marks.removeAll { $0.tool == .crop } }
            let points = tool == .curve ? [point,point,point] : [point,point]
            marks.append(Mark(tool:tool,points:points,color:ink,width:strokeWidth))
            selected = marks.count-1; isEditingPoints = tool == .curve; drawing = true
        }
        needsDisplay = true
    }
    private func segmentDistance(_ p: NSPoint, _ a: NSPoint, _ b: NSPoint) -> CGFloat {
        let dx=b.x-a.x, dy=b.y-a.y, length=dx*dx+dy*dy
        let t = length == 0 ? 0 : max(0,min(1,((p.x-a.x)*dx+(p.y-a.y)*dy)/length))
        return distance(p,NSPoint(x:a.x+t*dx,y:a.y+t*dy))
    }
    override func mouseDragged(with event: NSEvent) {
        guard let i = selected else { return }
        let p = convert(event.locationInWindow,from:nil)
        if drawing {
            if tool == .sketch {
                if distance(p,marks[i].points.last!) > 2 { marks[i].points.append(p) }
            } else {
                marks[i].points[marks[i].points.count-1] = p
                if tool == .curve { let a=marks[i].points[0]; marks[i].points[1] = NSPoint(x:(a.x+p.x)/2,y:(a.y+p.y)/2) }
            }
        } else if handle == -1 {
            let scale = max((p.x-textResizeRect.minX)/max(1,textResizeRect.width),
                            (p.y-textResizeRect.minY)/max(1,textResizeRect.height))
            marks[i].fontSize = max(6,min(300,textResizeSize*scale))
            textSize = marks[i].fontSize
            onEditingChanged?()
        } else if let j = handle { marks[i].points[j] = p }
        else {
            let dx=p.x-lastPoint.x, dy=p.y-lastPoint.y
            marks[i].points = marks[i].points.map { NSPoint(x:$0.x+dx,y:$0.y+dy) }
        }
        lastPoint = p; needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if drawing {
            let wasCrop = tool == .crop
            drawing = false
            tool = .select
            if wasCrop, let i = selected {
                let area = rect(marks[i]).intersection(bounds)
                selected = nil
                if area.width >= 1 && area.height >= 1 {
                    marks[i].points = [area.origin, NSPoint(x: area.maxX, y: area.maxY)]
                    showCommittedCrop()
                } else if let previous = history.popLast() {
                    marks = previous
                }
            }
        }
        needsDisplay = true
    }
    func render() -> NSImage? {
        guard let source = image.cgImage(forProposedRect:nil,context:nil,hints:nil),
              let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:source.width,pixelsHigh:source.height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),
              let context = NSGraphicsContext(bitmapImageRep:bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        context.cgContext.scaleBy(x:CGFloat(source.width)/imageBounds.width,y:CGFloat(source.height)/imageBounds.height)
        exporting = true; draw(imageBounds); exporting = false
        NSGraphicsContext.restoreGraphicsState()
        if let crop = marks.last(where: { $0.tool == .crop }) {
            let area = rect(crop).intersection(imageBounds)
            let sx = CGFloat(source.width)/imageBounds.width, sy = CGFloat(source.height)/imageBounds.height
            let pixels = NSRect(x:area.minX*sx,y:(imageBounds.height-area.maxY)*sy,width:area.width*sx,height:area.height*sy).integral
            if pixels.width > 0, pixels.height > 0, let cg = bitmap.cgImage?.cropping(to:pixels) {
                return NSImage(cgImage:cg,size:NSSize(width:area.width,height:area.height))
            }
        }
        let result = NSImage(size:image.size); result.addRepresentation(bitmap); return result
    }
}

private extension NSBezierPath {
    var cgPathForHitTesting: CGPath {
        let result = CGMutablePath()
        var points = [NSPoint](repeating:.zero,count:3)
        let flattened = self.flattened
        for i in 0..<flattened.elementCount {
            switch flattened.element(at:i,associatedPoints:&points) {
            case .moveTo: result.move(to:points[0])
            case .lineTo: result.addLine(to:points[0])
            case .curveTo: result.addCurve(to:points[2],control1:points[0],control2:points[1])
            case .closePath: result.closeSubpath()
            default: break
            }
        }
        return result
    }
}

/// NSScrollView otherwise anchors a document smaller than its viewport at an
/// edge. Negative clip origins keep small images centered at every zoom level.
final class MarkupClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var result = super.constrainBoundsRect(proposedBounds)
        guard let document = documentView else { return result }
        if document.frame.width < result.width {
            result.origin.x = document.frame.midX - result.width / 2
        }
        if document.frame.height < result.height {
            result.origin.y = document.frame.midY - result.height / 2
        }
        return result
    }
}
