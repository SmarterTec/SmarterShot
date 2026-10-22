import AppKit

/// A native toolbar with contextual popover controls around a non-destructive editor.
final class MarkupWindow: NSWindowController, NSWindowDelegate, NSToolbarDelegate, NSComboBoxDelegate {
    enum SaveDisposition { case replaceOriginal, copy }
    private static var editors: [MarkupWindow] = []
    let canvas: MarkupCanvas
    private let source: URL
    private let sourceAppName: String?
    private let onSave: (CaptureController.Shot) -> Void
    private var allowClose = false
    private var showingSaveSheet = false
    private var toolButtons: [MarkupCanvas.Tool: NSButton] = [:]
    private let dimensions = NSTextField(labelWithString: "")
    private let fill = NSButton(checkboxWithTitle: "Fill", target: nil, action: nil)
    private let fillColor = NSColorWell()
    private let color = NSColorWell()
    private let width = NSPopUpButton()
    private let font = NSPopUpButton()
    private let textSize = NSComboBox()
    private let textSection = NSStackView()
    private let cropSection = NSStackView()
    private let cropZoom = NSSlider(value: 1, minValue: 0.1, maxValue: 8, target: nil, action: nil)
    private let scroll = MarkupScrollView()
    let formatting = NSPopover()

    init(shot: CaptureController.Shot, onSave: @escaping (CaptureController.Shot) -> Void) {
        source = shot.url
        sourceAppName = shot.sourceAppName
        self.onSave = onSave
        canvas = MarkupCanvas(image: shot.image)
        let window = NSWindow(contentRect: NSRect(x:0,y:0,width:1240,height:800),
                              styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        super.init(window: window)
        window.title = shot.url.lastPathComponent
        window.subtitle = "Markup"
        window.minSize = NSSize(width:1000,height:600)
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        let toolbar = NSToolbar(identifier:"SmarterShot.Markup")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar

        let root = NSView()
        window.contentView = root
        scroll.contentView = MarkupClipView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.allowsMagnification = true
        scroll.minMagnification = 0.05
        scroll.maxMagnification = 8
        scroll.documentView = canvas
        scroll.backgroundColor = .underPageBackgroundColor
        scroll.borderType = .noBorder
        let inspector = NSView()
        let fields = NSStackView()
        fields.orientation = .vertical
        fields.alignment = .leading
        fields.spacing = 16
        inspector.addSubview(fields)
        fields.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            fields.leadingAnchor.constraint(equalTo:inspector.leadingAnchor,constant:16),
            fields.trailingAnchor.constraint(equalTo:inspector.trailingAnchor,constant:-16),
            fields.topAnchor.constraint(equalTo:inspector.topAnchor,constant:16),
            fields.bottomAnchor.constraint(equalTo:inspector.bottomAnchor,constant:-16)
        ])
        func row(_ label: String, _ control: NSView) -> NSStackView {
            let title = NSTextField(labelWithString:label)
            title.font = .systemFont(ofSize:12)
            let stack = NSStackView(views:[title,control]); stack.spacing = 6
            return stack
        }
        color.color = .systemBlue
        color.target = self; color.action = #selector(changeColor(_:))
        color.setAccessibilityLabel("Stroke color")
        color.widthAnchor.constraint(equalToConstant:44).isActive = true
        fields.addArrangedSubview(row("Stroke",color))
        width.addItems(withTitles:["Fine · 2 pt","Regular · 5 pt","Bold · 10 pt"])
        width.selectItem(at:1)
        width.target = self; width.action = #selector(changeWidth(_:))
        width.setAccessibilityLabel("Line width")
        fields.addArrangedSubview(width)
        fill.target = self; fill.action = #selector(changeFill(_:))
        fillColor.color = .systemBlue
        fillColor.target = self; fillColor.action = #selector(changeFill(_:))
        fillColor.setAccessibilityLabel("Fill color")
        fillColor.widthAnchor.constraint(equalToConstant:44).isActive = true
        fields.addArrangedSubview(fill); fields.addArrangedSubview(fillColor)
        textSection.orientation = .vertical; textSection.spacing = 10
        fields.addArrangedSubview(textSection)
        font.addItems(withTitles:["System"] + NSFontManager.shared.availableFontFamilies.sorted())
        font.target = self; font.action = #selector(changeFontFamily(_:))
        font.setAccessibilityLabel("Text font")
        font.widthAnchor.constraint(equalToConstant:160).isActive = true
        textSection.addArrangedSubview(font)
        textSize.addItems(withObjectValues:[12,16,18,24,32,48,64,96].map(String.init))
        textSize.stringValue = "24"
        textSize.target = self; textSize.action = #selector(changeTextSize(_:)); textSize.delegate = self
        textSize.setAccessibilityLabel("Text size")
        textSize.widthAnchor.constraint(equalToConstant:64).isActive = true
        textSection.addArrangedSubview(row("Size",textSize))
        cropSection.orientation = .vertical; cropSection.spacing = 8
        fields.addArrangedSubview(cropSection)
        cropZoom.target = self; cropZoom.action = #selector(changeCropZoom(_:))
        cropZoom.isContinuous = true
        cropZoom.setAccessibilityLabel("Image zoom within crop")
        cropZoom.widthAnchor.constraint(equalToConstant:100).isActive = true
        cropSection.addArrangedSubview(row("Image zoom",cropZoom))
        for (title,action) in [("New Frame",#selector(newCrop)),("Apply",#selector(applyCrop)),("Cancel",#selector(cancelCrop))] {
            let b = NSButton(title:title,target:self,action:action)
            b.bezelStyle = .rounded; cropSection.addArrangedSubview(b)
        }
        let controller = NSViewController()
        controller.view = inspector
        formatting.contentViewController = controller
        formatting.behavior = .semitransient
        formatting.animates = true
        dimensions.font = .monospacedDigitSystemFont(ofSize:11,weight:.regular)
        dimensions.textColor = .secondaryLabelColor
        let fit = NSButton(title:"Fit",target:self,action:#selector(fitImage))
        let minus = NSButton(image:NSImage(systemSymbolName:"minus.magnifyingglass",accessibilityDescription:"Zoom out")!,target:self,action:#selector(zoomOut))
        let plus = NSButton(image:NSImage(systemSymbolName:"plus.magnifyingglass",accessibilityDescription:"Zoom in")!,target:self,action:#selector(zoomIn))
        for button in [minus,fit,plus] { styleGlassButton(button) }
        let zoom = NSStackView(views:[minus,fit,plus]); zoom.spacing = 8
        let footer = NSView()
        for view in [dimensions,zoom] { footer.addSubview(view); view.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            dimensions.leadingAnchor.constraint(equalTo:footer.leadingAnchor,constant:16),dimensions.centerYAnchor.constraint(equalTo:footer.centerYAnchor),
            zoom.trailingAnchor.constraint(equalTo:footer.trailingAnchor,constant:-12),zoom.centerYAnchor.constraint(equalTo:footer.centerYAnchor)
        ])
        for view in [scroll,footer] { root.addSubview(view); view.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo:root.leadingAnchor),scroll.topAnchor.constraint(equalTo:root.topAnchor),
            scroll.trailingAnchor.constraint(equalTo:root.trailingAnchor),scroll.bottomAnchor.constraint(equalTo:footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo:root.leadingAnchor),footer.trailingAnchor.constraint(equalTo:root.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo:root.bottomAnchor),footer.heightAnchor.constraint(equalToConstant:42)
        ])
        canvas.onToolChanged = { [weak self] in self?.refreshInspector() }
        canvas.onEditingChanged = { [weak self] in self?.refreshInspector() }
        canvas.onSaveRequested = { [weak self] in self?.askToSave() }
        canvas.tool = .select
        window.center()
        Self.editors.append(self)
        showWindow(nil)
        NSApp.activate(ignoringOtherApps:true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
        root.layoutSubtreeIfNeeded()
        canvas.fitInViewport()
        refreshInspector()
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) not used") }
    static func isEditing(url:URL) -> Bool { editors.contains { $0.source == url } }
    static var hasUnsavedEditors: Bool { editors.contains { $0.canvas.hasUnsavedChanges } }
    static func reviewBeforeQuitting(completion:@escaping (Bool)->Void) {
        let open = editors
        func next(_ index:Int) {
            guard index < open.count else { completion(true); return }
            let editor = open[index]
            editor.canvas.endTextEditing()
            if editor.canvas.hasUnsavedChanges {
                editor.askToSave { accepted in
                    if accepted { next(index+1) } else { completion(false) }
                }
            } else { editor.allowClose = true; editor.close(); next(index+1) }
        }
        next(0)
    }
    private func refreshInspector() {
        for (tool,button) in toolButtons { button.state = canvas.tool == tool ? .on : .off }
        fill.isEnabled = canvas.canFill
        fill.state = canvas.selectedFillColor == nil ? .off : .on
        fillColor.isEnabled = canvas.canFill
        fillColor.color = canvas.selectedFillColor ?? canvas.fillInk
        textSection.isHidden = !(canvas.isTextSelected || canvas.tool == .text)
        cropSection.isHidden = !canvas.isCropping
        cropZoom.minValue = Double(canvas.minimumCropScale)
        cropZoom.doubleValue = Double(canvas.cropScale)
        font.selectItem(withTitle:canvas.selectedTextFamily)
        textSize.stringValue = String(Int(canvas.selectedTextSize.rounded()))
        if let ink = canvas.selectedColor { color.color = ink; canvas.ink = ink }
        let selectedWidth = canvas.selectedStrokeWidth
        canvas.strokeWidth = selectedWidth
        width.selectItem(at:[CGFloat(2),5,10].enumerated().min { abs($0.element-selectedWidth)<abs($1.element-selectedWidth) }!.offset)
        window?.isDocumentEdited = canvas.hasUnsavedChanges
        let size = canvas.outputSize
        dimensions.stringValue = "\(Int(size.width.rounded())) × \(Int(size.height.rounded())) px"

    }
    func toolbarDefaultItemIdentifiers(_ toolbar:NSToolbar) -> [NSToolbarItem.Identifier] {
        MarkupCanvas.Tool.allCases.map { .init("tool.\($0.rawValue)") } + [.init("format"),.flexibleSpace,.init("undo"),.init("redo"),.init("copy"),.init("save")]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar:NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbar(_ toolbar:NSToolbar,itemForItemIdentifier id:NSToolbarItem.Identifier,willBeInsertedIntoToolbar:Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier:id)
        if let index = MarkupCanvas.Tool.allCases.firstIndex(where:{id.rawValue == "tool.\($0.rawValue)"}) {
            let tool = MarkupCanvas.Tool.allCases[index]
            let symbols = ["cursorarrow","pencil.tip","point.topleft.down.to.point.bottomright.curvepath","line.diagonal","arrow.up.right","rectangle","oval","textformat","highlighter","crop"]
            let b = NSButton(image:NSImage(systemSymbolName:symbols[index],accessibilityDescription:tool.rawValue) ?? NSImage(),target:self,action:#selector(selectTool(_:)))
            b.title = ""; b.imagePosition = .imageOnly
            b.tag = index; b.setButtonType(.pushOnPushOff); styleGlassButton(b)
            b.toolTip = tool == .sketch ? "Sketch — draw and hold to recognize a shape" : tool.rawValue
            b.setAccessibilityLabel(tool.rawValue)
            b.widthAnchor.constraint(equalToConstant:32).isActive = true
            toolButtons[tool] = b
            if tool == .highlight { b.image = NSImage(size:NSSize(width:20,height:20),flipped:false) { rect in
                NSColor.systemYellow.setFill()
                NSBezierPath(roundedRect:NSRect(x:1,y:2,width:18,height:14),xRadius:2,yRadius:2).fill()
                ("A" as NSString).draw(at:NSPoint(x:4,y:2),withAttributes:[.font:NSFont.systemFont(ofSize:15,weight:.semibold),.foregroundColor:NSColor.black])
                return true
            } }
            item.view = b; item.label = tool.rawValue; item.paletteLabel = tool.rawValue
        } else {
            let title:String, symbol:String, action:Selector
            switch id.rawValue {
            case "format": (title,symbol,action) = ("Formatting","slider.horizontal.3",#selector(showFormatting(_:)))
            case "undo": (title,symbol,action) = ("Undo","arrow.uturn.backward",#selector(undoEdit))
            case "redo": (title,symbol,action) = ("Redo","arrow.uturn.forward",#selector(redoEdit))
            case "copy": (title,symbol,action) = ("Copy","doc.on.doc",#selector(copyImage))
            case "save": (title,symbol,action) = ("Save","square.and.arrow.down",#selector(saveAction))
            default: return nil
            }
            let b = id.rawValue == "save" ? NSButton(title:"Save…",target:self,action:action)
                : NSButton(image:NSImage(systemSymbolName:symbol,accessibilityDescription:title) ?? NSImage(),target:self,action:action)
            styleGlassButton(b); b.toolTip = title; b.setAccessibilityLabel(title)
            item.view = b; item.label = title
        }
        return item
    }
    private func styleGlassButton(_ button:NSButton) {
        if #available(macOS 26.0, *) { button.bezelStyle = .glass; button.borderShape = .capsule }
        else { button.bezelStyle = .texturedRounded }
    }
    @objc private func showFormatting(_ sender:NSButton) {
        if formatting.isShown { formatting.performClose(sender) }
        else {
            refreshInspector()
            formatting.contentViewController?.view.layoutSubtreeIfNeeded()
            formatting.contentSize = formatting.contentViewController!.view.fittingSize
            formatting.show(relativeTo:sender.bounds,of:sender,preferredEdge:.minY)
        }
    }
    @objc private func selectTool(_ sender:NSButton) {
        guard MarkupCanvas.Tool.allCases.indices.contains(sender.tag) else { return }
        canvas.endTextEditing()
        canvas.tool = MarkupCanvas.Tool.allCases[sender.tag]
        window?.makeFirstResponder(canvas)
    }
    @objc private func changeColor(_ sender:NSColorWell) { canvas.ink = sender.color; canvas.restyleSelection() }
    @objc private func changeWidth(_ sender:NSPopUpButton) { canvas.strokeWidth = [2,5,10][sender.indexOfSelectedItem]; canvas.restyleSelection() }
    @objc private func changeFontFamily(_ sender:NSPopUpButton) { canvas.setTextFamily(sender.titleOfSelectedItem ?? "System") }
    @objc private func changeTextSize(_ sender:NSComboBox) { if let n = Double(sender.stringValue),n.isFinite { canvas.setTextSize(n) } }
    func controlTextDidEndEditing(_ notification:Notification) { if let sender = notification.object as? NSComboBox { changeTextSize(sender) } }
    func comboBoxSelectionDidChange(_ notification:Notification) {
        guard let sender = notification.object as? NSComboBox,let value = sender.objectValueOfSelectedItem as? String,let n = Double(value) else { return }
        canvas.setTextSize(n)
    }
    @objc private func changeFill(_ sender:NSControl) {
        canvas.fillInk = fillColor.color
        if sender === fillColor { fill.state = .on }
        canvas.setFill(fill.state == .on ? fillColor.color : nil)
    }
    @objc private func newCrop() { canvas.startNewCrop(); window?.makeFirstResponder(canvas) }
    @objc private func applyCrop() { canvas.applyCrop(); window?.makeFirstResponder(canvas) }
    @objc private func cancelCrop() { canvas.cancelCrop(); window?.makeFirstResponder(canvas) }
    @objc private func changeCropZoom(_ sender:NSSlider) { canvas.setCropScale(sender.doubleValue) }
    @objc private func fitImage() { canvas.fitInViewport() }
    @objc private func zoomIn() { scroll.magnification = min(scroll.maxMagnification,scroll.magnification*1.25) }
    @objc private func zoomOut() { scroll.magnification = max(scroll.minMagnification,scroll.magnification/1.25) }
    @objc private func undoEdit() { canvas.undoEdit() }
    @objc private func redoEdit() { canvas.redoEdit() }
    @objc private func copyImage() {
        canvas.endTextEditing()
        guard let image = canvas.render() else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([image])
    }
    @objc private func saveAction() { askToSave() }
    func windowShouldClose(_ sender:NSWindow) -> Bool {
        canvas.endTextEditing()
        if allowClose || !canvas.hasUnsavedChanges { return true }
        askToSave()
        return false
    }
    func windowWillClose(_ notification:Notification) { Self.editors.removeAll { $0 === self } }
    private func askToSave(completion:((Bool)->Void)? = nil) {
        guard !showingSaveSheet,let window = window else { completion?(false); return }
        canvas.endTextEditing()
        showingSaveSheet = true
        let alert = NSAlert()
        alert.messageText = "Save changes to this screenshot?"
        alert.informativeText = "Save a separate copy or replace “\(source.lastPathComponent)”."
        alert.addButton(withTitle:"Save a Copy")
        alert.addButton(withTitle:"Replace Original")
        alert.addButton(withTitle:"Discard Changes")
        alert.addButton(withTitle:"Keep Editing").keyEquivalent = "\u{1b}"
        alert.beginSheetModal(for:window) { [weak self] response in
            guard let self = self else { return }
            self.showingSaveSheet = false
            switch response.rawValue {
            case NSApplication.ModalResponse.alertFirstButtonReturn.rawValue:
                let saved = self.saveEdits(.copy); completion?(saved)
            case NSApplication.ModalResponse.alertSecondButtonReturn.rawValue:
                let saved = self.saveEdits(.replaceOriginal); completion?(saved)
            case NSApplication.ModalResponse.alertThirdButtonReturn.rawValue: self.allowClose = true; self.close(); completion?(true)
            default: completion?(false)
            }
        }
    }
    @discardableResult func saveEdits(_ disposition:SaveDisposition) -> Bool {
        canvas.endTextEditing()
        if canvas.isCropping { canvas.applyCrop() }
        guard let image = canvas.render(),let tiff = image.tiffRepresentation,let bitmap = NSBitmapImageRep(data:tiff) else { return false }
        let destination:URL
        let type:NSBitmapImageRep.FileType
        if disposition == .replaceOriginal {
            destination = source
            switch source.pathExtension.lowercased() {
            case "png": type = .png
            case "jpg","jpeg": type = .jpeg
            case "tif","tiff": type = .tiff
            default:
                showError(NSError(domain:"SmarterShot",code:1,userInfo:[NSLocalizedDescriptionKey:"This file format cannot be replaced. Choose Save a Copy to create a PNG."]))
                return false
            }
        } else {
            let stem = source.deletingPathExtension().lastPathComponent + " — Markup"
            var candidate = source.deletingLastPathComponent().appendingPathComponent(stem+".png")
            var n = 2
            while FileManager.default.fileExists(atPath:candidate.path) {
                candidate = source.deletingLastPathComponent().appendingPathComponent("\(stem) (\(n)).png"); n += 1
            }
            destination = candidate; type = .png
        }
        guard let data = bitmap.representation(using:type,properties:type == .jpeg ? [.compressionFactor:0.95] : [:]) else { return false }
        do {
            try data.write(to:destination,options:.atomic)
            CaptureSourceContext.write(sourceAppName,to:destination)
            canvas.markSaved()
            onSave(CaptureController.Shot(url:destination,image:image))
            allowClose = true; close()
            return true
        } catch { showError(error); return false }
    }
    private func showError(_ error:Error) { if let window = window { NSAlert(error:error).beginSheetModal(for:window) } }
}

final class MarkupCanvas: NSView, NSTextFieldDelegate {
    enum Tool: String, CaseIterable { case select = "Select", sketch = "Sketch", curve = "Curve", line = "Line", arrow = "Arrow", rectangle = "Box", ellipse = "Oval", text = "Text", highlight = "Highlight", crop = "Crop" }
    struct Mark: Equatable {
        var tool: Tool
        var points: [NSPoint]
        var color: NSColor
        var width: CGFloat
        var text = ""
        var fontFamily = "System"
        var fillColor: NSColor? = nil
        var smoothPoints: Set<Int> = []
        var fontSize: CGFloat = 24
    }
    let image: NSImage
    var onToolChanged: (() -> Void)?
    var tool: Tool = .curve {
        didSet {
            if oldValue == .crop && tool != .crop && isCropping {
                if cropChanged { applyCrop(updateTool:false) } else { cancelCrop(updateTool:false) }
            }
            if tool == .crop && !isCropping { beginCrop() }
            onToolChanged?()
        }
    }
    var onSaveRequested: (() -> Void)?
    private var savedMarks: [Mark] = []
    var hasUnsavedChanges: Bool { marks != savedMarks || (isCropping && cropChanged) }
    var isTextSelected: Bool { selected.map { marks[$0].tool == .text } ?? false }
    func markSaved() { savedMarks = marks; notifyChange() }
    func endTextEditing() { finishTextEditing() }
    private func notifyChange() { needsDisplay = true; onEditingChanged?() }

    var ink: NSColor = .systemBlue
    var strokeWidth: CGFloat = 5
    var fillInk: NSColor = .systemBlue
    private var defaultFill: NSColor?
    private func isClosed(_ mark:Mark) -> Bool {
        [.rectangle,.ellipse,.highlight].contains(mark.tool) || (mark.points.count > 2 && distance(mark.points[0],mark.points.last!) < 1)
    }
    var canFill: Bool { selected.map { isClosed(marks[$0]) } ?? [.rectangle,.ellipse,.highlight].contains(tool) }
    var selectedFillColor: NSColor? { selected.map { marks[$0].fillColor } ?? defaultFill }
    func setFill(_ color:NSColor?) {
        defaultFill = color
        if let i = selected,isClosed(marks[i]) { checkpoint(); marks[i].fillColor = color }
        notifyChange()
    }
    private var textFamily = "System"
    private var textSize: CGFloat = 24
    private var textEditor: NSTextField?
    private var editingTextIndex: Int?
    private var textResizeRect = NSRect.zero
    private var textResizeSize: CGFloat = 24
    private var marks: [Mark] = []
    var selectedTextFamily: String { isTextSelected ? marks[selected!].fontFamily : textFamily }
    var selectedTextSize: CGFloat { isTextSelected ? marks[selected!].fontSize : textSize }
    var selectedColor: NSColor? { selected.map { marks[$0].color } }
    var selectedStrokeWidth: CGFloat { selected.map { marks[$0].width } ?? strokeWidth }
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
        if let i = selected, marks[i].tool == .text { checkpoint(); marks[i].fontFamily = family; refreshTextEditor(); notifyChange() }
    }
    func setTextSize(_ size: CGFloat) {
        textSize = max(6,min(300,size))
        if let i = selected, marks[i].tool == .text { checkpoint(); marks[i].fontSize = textSize; refreshTextEditor(); notifyChange() }
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
        notifyChange()
    }
    func controlTextDidChange(_ notification: Notification) {
        guard let i = editingTextIndex, let field = textEditor else { return }
        marks[i].text = field.stringValue; refreshTextEditor(); notifyChange()
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
    private(set) var isEditingPoints = false { didSet { onEditingChanged?(); notifyChange() } }
    var canEditPoints: Bool {
        guard let i = selected else { return false }
        return ![Tool.text, .crop].contains(marks[i].tool)
    }
    private var selected: Int? { didSet {
        if oldValue != selected { selectedPointIndices.removeAll() }
        onEditingChanged?()
    } }
    private(set) var selectedPointIndices: Set<Int> = []
    var selectionPointCount: Int { selected.map { editablePoints(marks[$0]).count } ?? 0 }
    func selectedPoint(at index:Int) -> NSPoint? {
        guard let i = selected,editablePoints(marks[i]).indices.contains(index) else { return nil }
        return editablePoints(marks[i])[index]
    }
    private func editablePoints(_ mark:Mark) -> [NSPoint] {
        guard mark.points.count == 2 else { return mark.points }
        let r = rect(mark)
        if mark.tool == .rectangle || mark.tool == .highlight {
            return [r.origin,NSPoint(x:r.maxX,y:r.minY),NSPoint(x:r.maxX,y:r.maxY),NSPoint(x:r.minX,y:r.maxY)]
        }
        if mark.tool == .ellipse {
            return (0..<8).map { index in
                let angle = CGFloat(index) * .pi / 4
                return NSPoint(x:r.midX+r.width/2*cos(angle),y:r.midY+r.height/2*sin(angle))
            }
        }
        return mark.points
    }
    private func prepareOutline(at i:Int) {
        let points = editablePoints(marks[i])
        if points != marks[i].points { checkpointGesture(); marks[i].points = points }
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

    private(set) var isCropping = false
    private(set) var cropFrame: NSRect?
    private var cropOffset = NSPoint.zero
    private(set) var cropScale: CGFloat = 1
    private var cropChanged = false
    private var cropDrag: Int? // -2 new frame, -1 image pan, 0...7 frame handles
    private var cropAnchor = NSPoint.zero
    private var cropStartFrame = NSRect.zero
    var minimumCropScale: CGFloat {
        guard let frame = cropFrame else { return 0.1 }
        return max(0.1,max(frame.width/imageBounds.width,frame.height/imageBounds.height))
    }
    private var cropImageRect: NSRect {
        NSRect(x:cropOffset.x,y:cropOffset.y,width:imageBounds.width*cropScale,height:imageBounds.height*cropScale)
    }
    private var draftSourceRect: NSRect? {
        guard let frame = cropFrame,frame.width >= 1,frame.height >= 1 else { return nil }
        let result = NSRect(x:(frame.minX-cropOffset.x)/cropScale,y:(frame.minY-cropOffset.y)/cropScale,
                            width:frame.width/cropScale,height:frame.height/cropScale).intersection(imageBounds)
        return result.width >= 1 && result.height >= 1 ? result : nil
    }
    var outputSize: NSSize {
        let area = isCropping ? (draftSourceRect ?? committedCrop) : committedCrop
        guard let cg = image.cgImage(forProposedRect:nil,context:nil,hints:nil) else { return area.size }
        return NSSize(width:area.width*CGFloat(cg.width)/imageBounds.width,height:area.height*CGFloat(cg.height)/imageBounds.height)
    }
    private func beginCrop() {
        endTextEditing()
        cropAnimation?.invalidate(); cropAnimation = nil; isAnimatingCrop = false
        isCropping = true
        cropScale = 1; cropOffset = .zero; cropChanged = false
        cropFrame = NSEqualRects(committedCrop,imageBounds) ? imageBounds.insetBy(dx:imageBounds.width*0.12,dy:imageBounds.height*0.12) : committedCrop
        selected = nil
        setFrameSize(imageBounds.size); bounds = imageBounds
        fitInViewport(); notifyChange()
    }
    func startNewCrop() {
        if !isCropping { tool = .crop }
        cropFrame = nil; cropDrag = nil
        cropScale = 1; cropOffset = .zero; cropChanged = false
        notifyChange()
    }
    private func clampCropOffset() {
        guard let frame = cropFrame else { return }
        cropOffset.x = max(frame.maxX-imageBounds.width*cropScale,min(frame.minX,cropOffset.x))
        cropOffset.y = max(frame.maxY-imageBounds.height*cropScale,min(frame.minY,cropOffset.y))
    }
    func setCropScale(_ value: CGFloat, centeredAt point: NSPoint? = nil) {
        guard isCropping, value.isFinite, let frame = cropFrame else { return }
        let next = max(minimumCropScale,min(8,value))
        let center = point.flatMap { frame.contains($0) ? $0 : nil } ?? NSPoint(x:frame.midX,y:frame.midY)
        let anchor = NSPoint(x:(center.x-cropOffset.x)/cropScale,y:(center.y-cropOffset.y)/cropScale)
        cropOffset = NSPoint(x:center.x-anchor.x*next,y:center.y-anchor.y*next)
        cropScale = next; clampCropOffset(); cropChanged = true; notifyChange()
    }
    func applyCrop(updateTool: Bool = true) {
        guard isCropping else { return }
        guard let area = draftSourceRect else { cancelCrop(updateTool:updateTool); return }
        checkpoint()
        marks.removeAll { $0.tool == .crop }
        marks.append(Mark(tool:.crop,points:[area.origin,NSPoint(x:area.maxX,y:area.maxY)],color:.clear,width:0))
        selected = nil
        isCropping = false; cropFrame = nil; cropChanged = false; cropDrag = nil
        if updateTool { onToolChanged?() }
        showCommittedCrop(); notifyChange()
    }
    func cancelCrop(updateTool: Bool = true) {
        guard isCropping else { return }
        isCropping = false; cropFrame = nil; cropChanged = false; cropDrag = nil
        if updateTool { onToolChanged?() }
        showCommittedCrop(); notifyChange()
    }
    private func cropHandles(_ frame: NSRect) -> [NSPoint] {
        [NSPoint(x:frame.minX,y:frame.minY),NSPoint(x:frame.midX,y:frame.minY),NSPoint(x:frame.maxX,y:frame.minY),
         NSPoint(x:frame.maxX,y:frame.midY),NSPoint(x:frame.maxX,y:frame.maxY),NSPoint(x:frame.midX,y:frame.maxY),
         NSPoint(x:frame.minX,y:frame.maxY),NSPoint(x:frame.minX,y:frame.midY)]
    }
    private func cropMouseDown(_ point: NSPoint) {
        cropAnchor = point
        if let frame = cropFrame {
            cropStartFrame = frame
            if let h = cropHandles(frame).firstIndex(where:{distance(point,$0)<hitRadius*1.2}) { cropDrag = h; return }
            if frame.contains(point) { cropDrag = -1; return }
        }
        cropDrag = -2
        cropFrame = NSRect(origin:point,size:.zero)
    }
    private func cropMouseDragged(_ point: NSPoint) {
        guard let drag = cropDrag else { return }
        if drag == -1 {
            cropOffset.x += point.x-lastPoint.x; cropOffset.y += point.y-lastPoint.y
            clampCropOffset()
        } else if drag == -2 {
            let proposed = NSRect(x:min(cropAnchor.x,point.x),y:min(cropAnchor.y,point.y),width:abs(point.x-cropAnchor.x),height:abs(point.y-cropAnchor.y))
            cropFrame = proposed.intersection(imageBounds).intersection(cropImageRect)
        } else {
            let r = cropStartFrame
            var minX = r.minX, maxX = r.maxX, minY = r.minY, maxY = r.maxY
            if [0,6,7].contains(drag) { minX = min(point.x,maxX-1) }
            if [2,3,4].contains(drag) { maxX = max(point.x,minX+1) }
            if [0,1,2].contains(drag) { minY = min(point.y,maxY-1) }
            if [4,5,6].contains(drag) { maxY = max(point.y,minY+1) }
            cropFrame = NSRect(x:minX,y:minY,width:maxX-minX,height:maxY-minY).intersection(imageBounds).intersection(cropImageRect)
        }
        cropChanged = true; lastPoint = point; notifyChange()
    }
    private func drawCropFrame() {
        guard let frame = cropFrame else { return }
        let mask = NSBezierPath(rect:bounds); mask.appendRect(frame); mask.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.5).setFill(); mask.fill()
        NSColor.white.setStroke()
        let border = NSBezierPath(rect:frame); border.lineWidth = hitRadius/8; border.stroke()
        let grid = NSBezierPath(); grid.lineWidth = hitRadius/18
        for n in 1...2 {
            let x = frame.minX+frame.width*CGFloat(n)/3, y = frame.minY+frame.height*CGFloat(n)/3
            grid.move(to:NSPoint(x:x,y:frame.minY)); grid.line(to:NSPoint(x:x,y:frame.maxY))
            grid.move(to:NSPoint(x:frame.minX,y:y)); grid.line(to:NSPoint(x:frame.maxX,y:y))
        }
        NSColor.white.withAlphaComponent(0.4).setStroke(); grid.stroke()
        NSColor.white.setFill()
        for point in cropHandles(frame) { NSBezierPath(roundedRect:NSRect(x:point.x-hitRadius/2,y:point.y-hitRadius/2,width:hitRadius,height:hitRadius),xRadius:hitRadius/5,yRadius:hitRadius/5).fill() }
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
            self.notifyChange()
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
    func undoEdit() { finishTextEditing(); if isCropping { cancelCrop(); return }; guard let previous = history.popLast() else { return }; future.append(marks); marks = previous; selected = nil; showCommittedCrop(); notifyChange() }
    func redoEdit() { finishTextEditing(); if isCropping { cancelCrop(); return }; guard let next = future.popLast() else { return }; history.append(marks); marks = next; selected = nil; showCommittedCrop(); notifyChange() }
    func deleteSelection() { finishTextEditing(); guard let i = selected else { return }; checkpoint(); marks.remove(at: i); selected = nil; showCommittedCrop(); notifyChange() }
    func restyleSelection() { guard let i = selected else { return }; checkpoint(); marks[i].color = ink; marks[i].width = strokeWidth; refreshTextEditor(); notifyChange() }
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "s" { onSaveRequested?(); return }
        if isCropping {
            if event.keyCode == 36 { applyCrop(); return }
            if event.keyCode == 53 { cancelCrop(); return }
        }
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
        if mark.tool == .crop || ([Tool.rectangle,.highlight].contains(mark.tool) && points.count == 2) { p.appendRect(rect(mark)); return p }
        if mark.tool == .ellipse && points.count == 2 { p.appendOval(in: rect(mark)); return p }
        let closed = isClosed(mark)
        p.move(to: points[0])
        if mark.tool == .curve || mark.tool == .sketch || mark.tool == .ellipse || !mark.smoothPoints.isEmpty {
            // Closed outlines wrap their neighboring points at the seam.
            for i in 0..<(closed ? points.count : points.count-1) {
                let a = points[closed ? (i-1+points.count)%points.count : max(0,i-1)]
                let b = points[i], c = points[(i+1)%points.count]
                let d = points[closed ? (i+2)%points.count : min(points.count-1,i+2)]
                let allSmooth = [.curve,.sketch,.ellipse].contains(mark.tool)
                let c1 = allSmooth || mark.smoothPoints.contains(i) ? NSPoint(x:b.x+(c.x-a.x)/6,y:b.y+(c.y-a.y)/6) : b
                let c2 = allSmooth || mark.smoothPoints.contains((i+1)%points.count) ? NSPoint(x:c.x-(d.x-b.x)/6,y:c.y-(d.y-b.y)/6) : c
                p.curve(to:c,controlPoint1:c1,controlPoint2:c2)
            }
        } else { for point in points.dropFirst() { p.line(to: point) } }
        if closed { p.close() }
        if mark.tool == .arrow, let end = points.last {
            let start = points[points.count-2], angle = atan2(end.y-start.y,end.x-start.x), length = max(15,mark.width*4)
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
        NSGraphicsContext.saveGraphicsState()
        if isCropping && !exporting {
            let transform = NSAffineTransform()
            transform.translateX(by:cropOffset.x,yBy:cropOffset.y)
            transform.scale(by:cropScale)
            transform.concat()
        }
        image.draw(in: imageBounds)
        for mark in marks {
            if mark.tool == .crop { continue }
            mark.color.setStroke()
            if mark.tool == .text {
                (mark.text as NSString).draw(at: mark.points[0], withAttributes: [.foregroundColor: mark.color, .font: font(for: mark)])
            } else if mark.tool == .highlight {
                (mark.fillColor ?? mark.color.withAlphaComponent(0.3)).setFill(); path(mark).fill()
            } else {
                if isClosed(mark),let fill = mark.fillColor { fill.setFill(); path(mark).fill() }
                path(mark).stroke()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        if isCropping && !exporting { drawCropFrame(); return }
        if !exporting, let i = selected, marks[i].tool == .text, editingTextIndex == nil {
            let r = textRect(marks[i])
            NSColor.systemBlue.setStroke()
            let border = NSBezierPath(rect:r.insetBy(dx:-3,dy:-3))
            border.lineWidth = hitRadius/10
            border.stroke()
            NSColor.systemBlue.setFill()
            NSBezierPath(rect:NSRect(x:r.maxX-hitRadius/2,y:r.maxY-hitRadius/2,width:hitRadius,height:hitRadius)).fill()
        }
        if !exporting,let area = pointMarquee {
            NSColor.selectedControlColor.withAlphaComponent(0.15).setFill(); area.fill()
            NSColor.selectedControlColor.setStroke(); NSBezierPath(rect:area).stroke()
        }
        if !exporting, isEditingPoints, canEditPoints, let i = selected {
            for (j, point) in editablePoints(marks[i]).enumerated() {
                let radius = hitRadius * 0.45
                let dot = NSBezierPath(ovalIn: NSRect(x:point.x-radius,y:point.y-radius,width:radius*2,height:radius*2))
                (selectedPointIndices.contains(j) ? NSColor.systemOrange : j == 0 || j == editablePoints(marks[i]).count-1 ? NSColor.systemBlue : NSColor.systemGreen).setFill()
                dot.fill(); NSColor.white.setStroke(); dot.lineWidth = radius/4; dot.stroke()
            }
        }
    }
    private var shapeTimer: Timer?
    private var rawSketch: [NSPoint]?
    private var pressTimer: Timer?
    private var pressOrigin = NSPoint.zero
    private var pressedExisting = false
    private var gestureCheckpointed = false
    private func checkpointGesture() {
        if !gestureCheckpointed { checkpoint(); gestureCheckpointed = true }
    }
    private var selectionDragged = false
    private var pointMarquee: NSRect?
    private var marqueeBase: Set<Int> = []
    private func hitMark(_ point:NSPoint) -> Int? {
        marks.indices.reversed().first { i in
            let m = marks[i]
            if m.tool == .crop { return false }
            if m.tool == .text { return textRect(m).insetBy(dx:-hitRadius,dy:-hitRadius).contains(point) }
            if (m.tool == .highlight || m.fillColor != nil) && path(m).contains(point) { return true }
            return path(m).cgPathForHitTesting.copy(strokingWithWidth:max(m.width,hitRadius*2),lineCap:.round,lineJoin:.round,miterLimit:10).contains(point)
        }
    }
    private func scheduleBend(_ point:NSPoint,at i:Int,node:Int?) {
        pressTimer = Timer(timeInterval:0.4,repeats:false) { [weak self] _ in
            guard let self = self,self.selected == i,!self.selectionDragged else { return }
            if self.marks[i].tool == .sketch {
                let node = node ?? self.marks[i].points.indices.min { self.distance(self.marks[i].points[$0],point) < self.distance(self.marks[i].points[$1],point) }!
                // A freehand stroke has dense samples. Make room around the
                // held node so dragging it creates a bend rather than a spike.
                let pts = self.marks[i].points
                var left = node, right = node
                while left > 0 && self.distance(pts[left-1],point) < self.hitRadius*3 { left -= 1 }
                while right < pts.count-1 && self.distance(pts[right+1],point) < self.hitRadius*3 { right += 1 }
                self.checkpointGesture()
                if right-left > 1 {
                    self.marks[i].points.replaceSubrange((left+1)..<right,with:[point])
                    self.handle = left+1
                }
            } else {
                self.prepareOutline(at:i)
                if node == nil { self.insertPoint(point,at:i) }
            }
            if let h = self.handle { self.checkpointGesture(); self.marks[i].smoothPoints.insert(h); self.selectedPointIndices = [h] }
            self.notifyChange()
        }
            RunLoop.main.add(pressTimer!,forMode:.common)
    }
    override func mouseDown(with event:NSEvent) {
        guard !isAnimatingCrop else { return }
        shapeTimer?.invalidate(); shapeTimer = nil; rawSketch = nil
        pressTimer?.invalidate(); pressTimer = nil
        finishTextEditing(); window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow,from:nil)
        lastPoint = point; pressOrigin = point; drawing = false; handle = nil
        pressedExisting = false; selectionDragged = false; gestureCheckpointed = false
        if tool == .crop && !isCropping { beginCrop() }
        if isCropping { cropMouseDown(point); return }
        if let i = selected,marks[i].tool == .text {
            let r = textRect(marks[i])
            if event.clickCount == 2 && r.contains(point) { checkpoint(); beginTextEditing(at:i); return }
            if distance(point,NSPoint(x:r.maxX,y:r.maxY)) < hitRadius {
                handle = -1; textResizeRect = r; textResizeSize = marks[i].fontSize; return
            }
        }
        if isEditingPoints,canEditPoints,let i = selected,
           let j = editablePoints(marks[i]).indices.first(where:{distance(point,editablePoints(marks[i])[$0])<hitRadius}) {
            handle = j; pressedExisting = true
            if event.modifierFlags.contains(.shift) {
                if selectedPointIndices.contains(j) { selectedPointIndices.remove(j); handle = nil }
                else { selectedPointIndices.insert(j) }
            } else if !selectedPointIndices.contains(j) { selectedPointIndices = [j] }
            if selectedPointIndices.count <= 1 && !event.modifierFlags.contains(.shift) { scheduleBend(point,at:i,node:j) }
            notifyChange(); return
        }
        if let i = hitMark(point) {
            selected = i; pressedExisting = true
            // Keep the active drawing tool during the gesture. A click adopts
            // this object's original tool; a drag moves the selected object.
            if canEditPoints {
                isEditingPoints = true
                if event.clickCount == 2 { prepareOutline(at:i); insertPoint(point,at:i); return }
                scheduleBend(point,at:i,node:nil)
            }
            notifyChange(); return
        }
        if event.modifierFlags.contains(.shift),canEditPoints {
            pointMarquee = NSRect(origin:point,size:.zero); marqueeBase = selectedPointIndices
            return
        }
        selected = nil
        selectedPointIndices.removeAll()
        if tool == .select { isEditingPoints = false; notifyChange(); return }
        checkpoint()
        if tool == .text {
            var mark = Mark(tool:.text,points:[point],color:ink,width:strokeWidth,text:"Text")
            mark.fontFamily = textFamily; mark.fontSize = textSize
            marks.append(mark); selected = marks.count-1; isEditingPoints = false
            beginTextEditing(at:marks.count-1)
        } else {
            let points = tool == .curve ? [point,point,point] : [point,point]
            var mark = Mark(tool:tool,points:points,color:ink,width:strokeWidth)
            mark.fillColor = defaultFill
            marks.append(mark); selected = marks.count-1
            isEditingPoints = tool == .curve; drawing = true
        }
        notifyChange()
    }
    private func insertPoint(_ point:NSPoint, at i:Int) {
        let pts = marks[i].points
        let closed = [.rectangle,.ellipse,.highlight].contains(marks[i].tool)
        guard pts.count >= 2 else { return }
        let segment = (0..<(closed ? pts.count : pts.count-1)).min {
            segmentDistance(point,pts[$0],pts[($0+1)%pts.count]) < segmentDistance(point,pts[$1],pts[($1+1)%pts.count])
        }!
        checkpointGesture()
        marks[i].smoothPoints = Set(marks[i].smoothPoints.map { $0 > segment ? $0+1 : $0 })
        marks[i].points.insert(point,at:segment+1)
        handle = segment+1; selectedPointIndices = [segment+1]
        notifyChange()
    }
    private func segmentDistance(_ p: NSPoint, _ a: NSPoint, _ b: NSPoint) -> CGFloat {
        let dx=b.x-a.x, dy=b.y-a.y, length=dx*dx+dy*dy
        let t = length == 0 ? 0 : max(0,min(1,((p.x-a.x)*dx+(p.y-a.y)*dy)/length))
        return distance(p,NSPoint(x:a.x+t*dx,y:a.y+t*dy))
    }
    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow,from:nil)
        if isCropping { cropMouseDragged(p); return }
        if pointMarquee != nil,let i = selected {
            let area = NSRect(x:min(p.x,pressOrigin.x),y:min(p.y,pressOrigin.y),width:abs(p.x-pressOrigin.x),height:abs(p.y-pressOrigin.y))
            pointMarquee = area
            selectedPointIndices = marqueeBase.union(editablePoints(marks[i]).indices.filter { area.contains(editablePoints(marks[i])[$0]) })
            notifyChange(); return
        }
        guard let i = selected else { return }
        if distance(p,pressOrigin) > hitRadius/3 { selectionDragged = true; pressTimer?.invalidate(); pressTimer = nil }
        if !drawing { checkpointGesture() }
        if drawing {
            if tool == .sketch {
                shapeTimer?.invalidate(); shapeTimer = nil
                if let raw = rawSketch { marks[i].tool = .sketch; marks[i].points = raw; rawSketch = nil }
                if distance(p,marks[i].points.last!) > 2 { marks[i].points.append(p) }
                shapeTimer = Timer(timeInterval:0.55,repeats:false) { [weak self] _ in self?.recognizeHeldSketch() }
                RunLoop.main.add(shapeTimer!,forMode:.common)
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
        } else if let j = handle {
            prepareOutline(at:i)
            if selectedPointIndices.count > 1 {
                let delta = NSPoint(x:p.x-lastPoint.x,y:p.y-lastPoint.y)
                for index in selectedPointIndices where marks[i].points.indices.contains(index) {
                    marks[i].points[index].x += delta.x; marks[i].points[index].y += delta.y
                }
            } else { marks[i].points[j] = p }
        }
        else {
            let dx=p.x-lastPoint.x, dy=p.y-lastPoint.y
            marks[i].points = marks[i].points.map { NSPoint(x:$0.x+dx,y:$0.y+dy) }
        }
        lastPoint = p; notifyChange()
    }
    override func mouseUp(with event: NSEvent) {
        shapeTimer?.invalidate(); shapeTimer = nil; rawSketch = nil
        if pointMarquee != nil { pointMarquee = nil; notifyChange(); return }
        if isCropping { cropDrag = nil; notifyChange(); return }
        pressTimer?.invalidate(); pressTimer = nil
        if drawing {
            drawing = false
            if let i = selected,marks[i].tool == .sketch,marks[i].points.count > 3,
               distance(marks[i].points[0],marks[i].points.last!) < hitRadius {
                marks[i].points[marks[i].points.count-1] = marks[i].points[0]
            }
        } else if pressedExisting,let i = selected { tool = marks[i].tool }
        pressedExisting = false
        notifyChange()
    }
    override func magnify(with event:NSEvent) {
        if isCropping { magnifyCrop(by:event.magnification) }
        else { super.magnify(with:event) }
    }
    func magnifyCrop(by delta:CGFloat) { if isCropping { setCropScale(cropScale * max(0.1,1+delta)) } }
    private func recognizeHeldSketch() {
        guard drawing,tool == .sketch,let i = selected,marks[i].points.count >= 4 else { return }
        let points = marks[i].points
        let minX = points.map(\.x).min()!, maxX = points.map(\.x).max()!
        let minY = points.map(\.y).min()!, maxY = points.map(\.y).max()!
        let box = NSRect(x:minX,y:minY,width:maxX-minX,height:maxY-minY)
        let diagonal = hypot(box.width,box.height)
        guard diagonal > hitRadius*2 else { return }
        let closed = distance(points[0],points.last!) < max(hitRadius*2,diagonal*0.18)
        rawSketch = points
        if closed && box.width > hitRadius && box.height > hitRadius {
            let ellipseError = points.reduce(CGFloat(0)) { error,p in
                error + abs(hypot((p.x-box.midX)/(box.width/2),(p.y-box.midY)/(box.height/2))-1)
            } / CGFloat(points.count)
            let rectangleError = points.reduce(CGFloat(0)) { error,p in
                error + min(min(p.x-minX,maxX-p.x),min(p.y-minY,maxY-p.y))/diagonal
            } / CGFloat(points.count)
            if rectangleError < 0.025 {
                marks[i].tool = .rectangle; marks[i].points = [box.origin,NSPoint(x:maxX,y:maxY)]
            } else if ellipseError < 0.18 {
                marks[i].tool = .ellipse; marks[i].points = [box.origin,NSPoint(x:maxX,y:maxY)]
            } else {
                let simplified = simplify(points,tolerance:diagonal*0.05)
                marks[i].tool = .line; marks[i].points = simplified
                marks[i].points[marks[i].points.count-1] = marks[i].points[0]
            }
        } else {
            let simplified = simplify(points,tolerance:diagonal*0.035)
            marks[i].tool = simplified.count <= 2 ? .line : .curve
            marks[i].points = simplified
        }
        isEditingPoints = false; notifyChange()
    }
    private func simplify(_ points:[NSPoint],tolerance:CGFloat) -> [NSPoint] {
        guard points.count > 2 else { return points }
        let index = (1..<points.count-1).max { segmentDistance(points[$0],points[0],points.last!) < segmentDistance(points[$1],points[0],points.last!) }!
        if segmentDistance(points[index],points[0],points.last!) <= tolerance { return [points[0],points.last!] }
        return Array(simplify(Array(points[...index]),tolerance:tolerance).dropLast()) + simplify(Array(points[index...]),tolerance:tolerance)
    }
    func render() -> NSImage? {
        guard let source = image.cgImage(forProposedRect:nil,context:nil,hints:nil),
              let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:source.width,pixelsHigh:source.height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),
              let context = NSGraphicsContext(bitmapImageRep:bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        context.cgContext.scaleBy(x:CGFloat(source.width)/imageBounds.width,y:CGFloat(source.height)/imageBounds.height)
        exporting = true; draw(imageBounds); exporting = false
        NSGraphicsContext.restoreGraphicsState()
        let area = isCropping ? (draftSourceRect ?? committedCrop) : committedCrop
        if !NSEqualRects(area,imageBounds) {
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

/// Wheel zooms the image; trackpad scrolling still pans and pinching still zooms.
/// Crop zoom transforms the source behind its fixed frame, not the viewport.
final class MarkupScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        // Precise scrolling is used by trackpads/Magic Mouse. Option-scroll also
        // provides zoom for those devices without taking away two-finger panning.
        guard !event.hasPreciseScrollingDeltas || event.modifierFlags.contains(.option) else {
            super.scrollWheel(with:event); return
        }
        let delta = event.scrollingDeltaY
        guard delta.isFinite, delta != 0, abs(delta) >= abs(event.scrollingDeltaX),
              let canvas = documentView as? MarkupCanvas else {
            super.scrollWheel(with:event); return
        }
        let sensitivity: CGFloat = event.hasPreciseScrollingDeltas ? 0.01 : 0.08
        let factor = exp(max(-0.7,min(0.7,delta * sensitivity)))
        if canvas.isCropping {
            canvas.setCropScale(canvas.cropScale * factor, centeredAt:canvas.convert(event.locationInWindow,from:nil))
        } else {
            let next = max(minMagnification,min(maxMagnification,magnification * factor))
            setMagnification(next,centeredAt:contentView.convert(event.locationInWindow,from:nil))
        }
    }
    override func magnify(with event:NSEvent) {
        if let canvas = documentView as? MarkupCanvas,canvas.isCropping { canvas.magnify(with:event) }
        else { super.magnify(with:event) }
    }
}
