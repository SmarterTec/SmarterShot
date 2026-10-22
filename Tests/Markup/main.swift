import AppKit

// Standalone AppKit harness, without starting capture services or global hotkeys.
enum CaptureController {
    struct Shot { let url: URL; let image: NSImage }
    static func copyToClipboard(_ shot: Shot) {}
}
let app = NSApplication.shared
let rep = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:400,pixelsHigh:300,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:rep)
NSColor.white.setFill(); NSRect(x:0,y:0,width:400,height:300).fill()
NSGraphicsContext.restoreGraphicsState()
let source = NSImage(size:NSSize(width:400,height:300)); source.addRepresentation(rep)
// Every scenario starts with a clean canvas so overlapping objects do not
// accidentally exercise selection when the test intends to draw a new object.
func fixture() -> (MarkupCanvas,NSWindow) {
    let c = MarkupCanvas(image:source)
    let w = NSWindow(contentRect:c.bounds,styleMask:[.borderless],backing:.buffered,defer:false)
    w.contentView = c
    return (c,w)
}
func ev(_ c:MarkupCanvas,_ type:NSEvent.EventType,_ p:NSPoint,clicks:Int=1,flags:NSEvent.ModifierFlags=[]) -> NSEvent {
    NSEvent.mouseEvent(with:type,location:c.convert(p,to:nil),modifierFlags:flags,timestamp:0,windowNumber:c.window!.windowNumber,context:nil,eventNumber:0,clickCount:clicks,pressure:1)!
}
func gesture(_ c:MarkupCanvas,_ a:NSPoint,_ b:NSPoint,clicks:Int=1,hold:Bool=false) {
    c.mouseDown(with:ev(c,.leftMouseDown,a,clicks:clicks))
    if hold { RunLoop.main.run(until:Date(timeIntervalSinceNow:0.45)) }
    c.mouseDragged(with:ev(c,.leftMouseDragged,b))
    c.mouseUp(with:ev(c,.leftMouseUp,b))
}
for shape in [MarkupCanvas.Tool.line,.arrow,.rectangle,.ellipse,.curve,.sketch,.highlight] {
    let (c,w) = fixture(); _ = w
    c.tool = shape
    gesture(c,NSPoint(x:40,y:60),NSPoint(x:340,y:220))
    assert(c.tool == shape,"Drawing must retain the active tool")
    // Select an edge with a different active tool, adopting the object's tool.
    c.markSaved()
    c.tool = .text
    let point:NSPoint
    switch shape {
    case .rectangle,.highlight: point = NSPoint(x:180,y:60)
    case .ellipse: point = NSPoint(x:340,y:140)
    default: point = NSPoint(x:115,y:100)
    }
    c.mouseDown(with:ev(c,.leftMouseDown,point))
    c.mouseUp(with:ev(c,.leftMouseUp,point))
    assert(!c.hasUnsavedChanges,"Selecting a shape must not alter its geometry or dirty the document")
    assert(c.tool == shape && c.isEditingPoints,"Clicking an object selects its own tool and exposes points")
    let before = c.selectionPointCount
    let insert = shape == .ellipse ? NSPoint(x:190+150*cos(CGFloat.pi/8),y:140+80*sin(CGFloat.pi/8)) : point
    gesture(c,insert,NSPoint(x:insert.x,y:insert.y+20),clicks:2)
    assert(c.selectionPointCount == before+1,"Double-click adds points to every outline")
    c.undoEdit(); c.redoEdit()
    assert(c.render() != nil)
}
print("Direct editing passed: persistent tools, object/tool selection, double-click point insertion, undo/redo.")
let (bend,bendWindow) = fixture()
bend.tool = .line
gesture(bend,NSPoint(x:30,y:100),NSPoint(x:370,y:100))
gesture(bend,NSPoint(x:200,y:100),NSPoint(x:200,y:170),hold:true)
assert(bend.selectionPointCount == 3 && bend.selectedPoint(at:1) == NSPoint(x:200,y:170))
let bent = NSBitmapImageRep(data:bend.render()!.tiffRepresentation!)!
let ink = bent.colorAt(x:200,y:130)!.usingColorSpace(.deviceRGB)!
assert(ink.blueComponent > ink.redComponent+0.2,"Held edge must bend through the dragged smooth node")
assert(bend.tool == .line)
bend.undoEdit()
assert(bend.render() != nil)
let (sketch,sketchWindow) = fixture()
sketch.tool = .sketch
sketch.mouseDown(with:ev(sketch,.leftMouseDown,NSPoint(x:30,y:100)))
for x in stride(from:33,through:369,by:3) { sketch.mouseDragged(with:ev(sketch,.leftMouseDragged,NSPoint(x:x,y:100))) }
sketch.mouseUp(with:ev(sketch,.leftMouseUp,NSPoint(x:369,y:100)))
assert(!sketch.isEditingPoints)
let samples = sketch.selectionPointCount
gesture(sketch,NSPoint(x:201,y:100),NSPoint(x:201,y:160),hold:true)
assert(sketch.selectionPointCount < samples,"Holding a dense sketch must make room for a smooth bend")
print("Hold-to-bend passed for straight and densely sampled freehand strokes.")
for shape in [MarkupCanvas.Tool.rectangle,.ellipse] {
    let (c,w) = fixture(); _ = w
    c.tool = shape
    gesture(c,NSPoint(x:50,y:50),NSPoint(x:350,y:250))
    assert(c.canFill)
    c.setFill(.red)
    let b = NSBitmapImageRep(data:c.render()!.tiffRepresentation!)!
    let red = b.colorAt(x:200,y:150)!.usingColorSpace(.deviceRGB)!
    assert(red.redComponent > 0.9 && red.greenComponent < 0.2,"Fill must export inside closed shapes")
    c.undoEdit()
    let undone = NSBitmapImageRep(data:c.render()!.tiffRepresentation!)!.colorAt(x:200,y:150)!.usingColorSpace(.deviceRGB)!
    assert(undone.greenComponent > 0.9,"Undo must remove exported fill")
    c.redoEdit()
}
assert(!bend.canFill,"An open line cannot be filled")
print("Closed-shape fill passed, including exported pixels and undo/redo.")
let (text,textWindow) = fixture()
text.tool = .text
text.mouseDown(with:ev(text,.leftMouseDown,NSPoint(x:50,y:50)))
assert(text.tool == .text,"Text must keep its tool active")
let field = text.subviews.compactMap { $0 as? NSTextField }.first!
field.stringValue = "Move me"
text.controlTextDidChange(Notification(name:NSControl.textDidChangeNotification,object:field))
text.endTextEditing()
gesture(text,NSPoint(x:60,y:60),NSPoint(x:100,y:90))
assert(text.selectedPoint(at:0) == NSPoint(x:90,y:80))
text.setTextFamily("Helvetica"); text.setTextSize(32)
assert(text.selectedTextFamily == "Helvetica" && text.selectedTextSize == 32)
print("Inline text passed: persistent tool, selection, movement and formatting.")
let editor = MarkupWindow(shot:CaptureController.Shot(url:URL(fileURLWithPath:"/tmp/markup-toolbar-test.png"),image:source)) { _ in }
let toolButtons = editor.window!.toolbar!.items.filter { $0.itemIdentifier.rawValue.hasPrefix("tool.") }.compactMap { $0.view as? NSButton }
for tool in MarkupCanvas.Tool.allCases {
    let button = toolButtons.first { $0.tag == MarkupCanvas.Tool.allCases.firstIndex(of:tool)! }!
    assert(NSApp.sendAction(button.action!,to:button.target,from:button))
    assert(editor.canvas.tool == tool && button.state == .on)
}
func descendants(_ view:NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
let views = descendants(editor.window!.contentView!)
assert(!views.compactMap { $0 as? NSButton }.contains { ["Edit Points","Add Point"].contains($0.title) })
let formatButton = editor.window!.toolbar!.items.first { $0.itemIdentifier.rawValue == "format" }!.view as! NSButton
assert(NSApp.sendAction(formatButton.action!,to:formatButton.target,from:formatButton))
assert(editor.formatting.isShown,"Formatting must open from the main toolbar")
assert(descendants(editor.formatting.contentViewController!.view).compactMap { $0 as? NSButton }.contains { $0.title == "Fill" })
assert(!views.compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("Drag points") })
assert(toolButtons.allSatisfy { $0.title.isEmpty },"Drawing tools must all be icon-only")
editor.formatting.performClose(nil)
editor.close()
print("Native toolbar/layout passed: toolbar popover, icon-only tools, no hint text or point-editing buttons, all tool actions.")

// Holding at the end of a freehand stroke recognizes a clean shape.
for shape in [MarkupCanvas.Tool.rectangle,.ellipse,.line] {
    let (c,w) = fixture(); _ = w
    c.tool = .sketch
    let samples:[NSPoint]
    if shape == .rectangle {
        samples = [NSPoint(x:50,y:50),NSPoint(x:180,y:51),NSPoint(x:300,y:50),NSPoint(x:300,y:150),NSPoint(x:300,y:250),NSPoint(x:180,y:249),NSPoint(x:50,y:250),NSPoint(x:51,y:150),NSPoint(x:50,y:52)]
    } else if shape == .ellipse {
        samples = (0...32).map { n in let a = CGFloat(n)*2*CGFloat.pi/32; return NSPoint(x:200+140*cos(a),y:150+90*sin(a)) }
    } else { samples = (0...20).map { NSPoint(x:30+CGFloat($0)*16,y:100+CGFloat($0%2)) } }
    c.mouseDown(with:ev(c,.leftMouseDown,samples[0]))
    for p in samples.dropFirst() { c.mouseDragged(with:ev(c,.leftMouseDragged,p)) }
    RunLoop.main.run(until:Date(timeIntervalSinceNow:0.65))
    c.mouseUp(with:ev(c,.leftMouseUp,samples.last!))
    c.tool = .select
    let hit = shape == .ellipse ? NSPoint(x:340,y:150) : shape == .rectangle ? NSPoint(x:180,y:50) : NSPoint(x:190,y:100)
    c.mouseDown(with:ev(c,.leftMouseDown,hit)); c.mouseUp(with:ev(c,.leftMouseUp,hit))
    assert(c.tool == shape,"Draw-and-hold must recognize \(shape)")
    c.undoEdit(); assert(!c.hasUnsavedChanges,"Recognized drawing must undo in one step")
}
let (multi,multiWindow) = fixture()
multi.tool = .rectangle
gesture(multi,NSPoint(x:50,y:50),NSPoint(x:300,y:250))
multi.mouseDown(with:ev(multi,.leftMouseDown,NSPoint(x:180,y:50)))
multi.mouseUp(with:ev(multi,.leftMouseUp,NSPoint(x:180,y:50)))
for point in [NSPoint(x:50,y:50),NSPoint(x:300,y:50)] {
    multi.mouseDown(with:ev(multi,.leftMouseDown,point,flags:.shift))
    multi.mouseUp(with:ev(multi,.leftMouseUp,point,flags:.shift))
}
assert(multi.selectedPointIndices == [0,1])
gesture(multi,NSPoint(x:50,y:50),NSPoint(x:70,y:80))
assert(multi.selectedPoint(at:0) == NSPoint(x:70,y:80) && multi.selectedPoint(at:1) == NSPoint(x:320,y:80))
assert(multi.selectedPoint(at:2) == NSPoint(x:300,y:250),"Unselected points must stay fixed")
multi.undoEdit(); multi.redoEdit()
// Shift-drag a selection box, then move the selected group together.
multi.mouseDown(with:ev(multi,.leftMouseDown,NSPoint(x:180,y:80)))
multi.mouseUp(with:ev(multi,.leftMouseUp,NSPoint(x:180,y:80)))
multi.mouseDown(with:ev(multi,.leftMouseDown,NSPoint(x:10,y:10),flags:.shift))
multi.mouseDragged(with:ev(multi,.leftMouseDragged,NSPoint(x:390,y:290),flags:.shift))
multi.mouseUp(with:ev(multi,.leftMouseUp,NSPoint(x:390,y:290),flags:.shift))
assert(multi.selectedPointIndices.count == 4)
let fixed = multi.selectedPoint(at:2)!
gesture(multi,multi.selectedPoint(at:0)!,NSPoint(x:80,y:90))
assert(multi.selectedPoint(at:2)! == NSPoint(x:fixed.x+10,y:fixed.y+10))
// A brief pause may snap a stroke, but continuing to draw must restore it.
let (resume,resumeWindow) = fixture()
resume.tool = .sketch
resume.mouseDown(with:ev(resume,.leftMouseDown,NSPoint(x:20,y:100)))
for x in stride(from:30,through:200,by:10) { resume.mouseDragged(with:ev(resume,.leftMouseDragged,NSPoint(x:x,y:100))) }
RunLoop.main.run(until:Date(timeIntervalSinceNow:0.65))
assert(resume.selectionPointCount == 2)
resume.mouseDragged(with:ev(resume,.leftMouseDragged,NSPoint(x:220,y:170)))
resume.mouseUp(with:ev(resume,.leftMouseUp,NSPoint(x:220,y:170)))
assert(resume.selectionPointCount > 10 && resume.tool == .sketch)
print("Draw-and-hold recognition and Shift multi-point movement passed.")

// Crop is a reversible draft. Pan moves the source behind a fixed crop frame;
// zoom changes the source region, and frame handles resize without applying it.
let cropCanvas = MarkupCanvas(image:source)
let cropWindow = NSWindow(contentRect:cropCanvas.bounds,styleMask:[.borderless],backing:.buffered,defer:false)
cropWindow.contentView = cropCanvas
func ce(_ type:NSEvent.EventType,_ p:NSPoint) -> NSEvent {
    NSEvent.mouseEvent(with:type,location:cropCanvas.convert(p,to:nil),modifierFlags:[],timestamp:0,windowNumber:cropWindow.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
}
assert(!cropCanvas.hasUnsavedChanges)
cropCanvas.tool = .crop
assert(!cropCanvas.hasUnsavedChanges,"Entering crop alone must not dirty the document")
let fixedFrame = cropCanvas.cropFrame!
let center = NSPoint(x:fixedFrame.midX,y:fixedFrame.midY)
cropCanvas.mouseDown(with:ce(.leftMouseDown,center))
cropCanvas.mouseDragged(with:ce(.leftMouseDragged,NSPoint(x:center.x+20,y:center.y+10)))
cropCanvas.mouseUp(with:ce(.leftMouseUp,NSPoint(x:center.x+20,y:center.y+10)))
assert(cropCanvas.cropFrame == fixedFrame,"Panning the image must leave the crop frame fixed")
assert(cropCanvas.hasUnsavedChanges)
let beforeZoom = cropCanvas.outputSize
cropCanvas.magnifyCrop(by:1)
assert(cropCanvas.cropScale == 2)
assert(cropCanvas.outputSize.width < beforeZoom.width && cropCanvas.cropFrame == fixedFrame)
let cropCorner = NSPoint(x:fixedFrame.maxX,y:fixedFrame.maxY)
cropCanvas.mouseDown(with:ce(.leftMouseDown,cropCorner))
cropCanvas.mouseDragged(with:ce(.leftMouseDragged,NSPoint(x:cropCorner.x-30,y:cropCorner.y-20)))
cropCanvas.mouseUp(with:ce(.leftMouseUp,NSPoint(x:cropCorner.x-30,y:cropCorner.y-20)))
assert(cropCanvas.cropFrame!.width < fixedFrame.width,"Crop frame must resize from its handles")
cropCanvas.cancelCrop()
assert(!cropCanvas.hasUnsavedChanges && cropCanvas.bounds.size == source.size,"Cancel must restore the original without edits")
cropCanvas.tool = .crop
cropCanvas.setCropScale(2)
let output = cropCanvas.outputSize
cropCanvas.applyCrop()
assert(cropCanvas.hasUnsavedChanges)
let result = NSBitmapImageRep(data:cropCanvas.render()!.tiffRepresentation!)!
assert(abs(CGFloat(result.pixelsWide)-output.width)<2 && abs(CGFloat(result.pixelsHigh)-output.height)<2)
cropCanvas.undoEdit()
assert(!cropCanvas.hasUnsavedChanges,"Undoing the only edit must restore a clean document")
print("Crop draft checks passed: image pan, image zoom, frame resize, cancel, apply, export, and dirty state.")

// Route real line-wheel events to view zoom or the crop source transform.
let wheelCanvas = MarkupCanvas(image:source)
let wheelScroll = MarkupScrollView(frame:NSRect(x:0,y:0,width:320,height:240))
wheelScroll.contentView = MarkupClipView()
wheelScroll.allowsMagnification = true; wheelScroll.minMagnification = 0.05; wheelScroll.maxMagnification = 8
wheelScroll.documentView = wheelCanvas
let wheelWindow = NSWindow(contentRect:wheelScroll.frame,styleMask:[.borderless],backing:.buffered,defer:false)
wheelWindow.contentView = wheelScroll
func wheel(_ delta:Int32, precise:Bool=false, option:Bool=false) -> NSEvent {
    let cg = CGEvent(scrollWheelEvent2Source:nil,units:precise ? .pixel : .line,wheelCount:1,wheel1:delta,wheel2:0,wheel3:0)!
    if option { cg.flags = .maskAlternate }
    return NSEvent(cgEvent:cg)!
}
let viewZoom = wheelScroll.magnification
wheelScroll.scrollWheel(with:wheel(3))
assert(wheelScroll.magnification > viewZoom && !wheelCanvas.hasUnsavedChanges)
wheelScroll.scrollWheel(with:wheel(-3))
assert(abs(wheelScroll.magnification-viewZoom) < 0.001)
wheelScroll.scrollWheel(with:wheel(30,precise:true))
assert(abs(wheelScroll.magnification-viewZoom) < 0.001,"Trackpad scrolling should still pan")
wheelScroll.scrollWheel(with:wheel(30,precise:true,option:true))
assert(wheelScroll.magnification > viewZoom,"Option-scroll also zooms precise devices")
wheelCanvas.tool = .crop
let wheelCropFrame = wheelCanvas.cropFrame!, cropViewZoom = wheelScroll.magnification
wheelScroll.scrollWheel(with:wheel(3))
assert(wheelCanvas.cropScale > 1 && wheelCanvas.cropFrame == wheelCropFrame)
assert(wheelScroll.magnification == cropViewZoom,"Crop wheel must change source scale, not viewport zoom")
wheelScroll.scrollWheel(with:wheel(1000))
assert(wheelCanvas.cropScale <= 8)
for _ in 0..<12 { wheelScroll.scrollWheel(with:wheel(-1000)) }
assert(wheelCanvas.cropScale >= wheelCanvas.minimumCropScale && wheelCanvas.cropFrame == wheelCropFrame)
wheelCanvas.cancelCrop()
assert(!wheelCanvas.hasUnsavedChanges)
wheelWindow.close()
print("Mouse wheel checks passed: markup zoom, crop source zoom, fixed frame, scale limits and precise-device panning.")

// Exercise the native close sheet and actual atomic file writes in test fixtures.
let fixtures = URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent(".build/markup-tests/fixtures")
try FileManager.default.createDirectory(at:fixtures,withIntermediateDirectories:true)
let originalURL = fixtures.appendingPathComponent("original-\(UUID().uuidString).png")
let originalData = rep.representation(using:.png,properties:[:])!
try originalData.write(to:originalURL)
var savedURL:URL?
let saveEditor = MarkupWindow(shot:CaptureController.Shot(url:originalURL,image:source)) { savedURL = $0.url }
func drawIn(_ editor:MarkupWindow) {
    let c = editor.canvas
    func ev(_ type:NSEvent.EventType,_ p:NSPoint) -> NSEvent {
        NSEvent.mouseEvent(with:type,location:c.convert(p,to:nil),modifierFlags:[],timestamp:0,windowNumber:editor.window!.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
    }
    c.tool = .line
    c.mouseDown(with:ev(.leftMouseDown,NSPoint(x:40,y:50)))
    c.mouseDragged(with:ev(.leftMouseDragged,NSPoint(x:250,y:180)))
    c.mouseUp(with:ev(.leftMouseUp,NSPoint(x:250,y:180)))
}
assert(saveEditor.windowShouldClose(saveEditor.window!),"Unchanged screenshots must close without a sheet")
drawIn(saveEditor)
assert(!saveEditor.windowShouldClose(saveEditor.window!),"Edited screenshots must not close without a decision")
RunLoop.main.run(until:Date(timeIntervalSinceNow:0.05))
let sheet = saveEditor.window!.attachedSheet!
func allViews(_ root:NSView) -> [NSView] { [root] + root.subviews.flatMap(allViews) }
let choices = allViews(sheet.contentView!).compactMap { $0 as? NSButton }.map(\.title)
for title in ["Save a Copy","Replace Original","Discard Changes","Keep Editing"] { assert(choices.contains(title),"Missing close choice: \(title)") }
saveEditor.window!.endSheet(sheet,returnCode:NSApplication.ModalResponse(rawValue:NSApplication.ModalResponse.alertFirstButtonReturn.rawValue+3))
RunLoop.main.run(until:Date(timeIntervalSinceNow:0.1))
assert(saveEditor.canvas.hasUnsavedChanges && saveEditor.window!.isVisible,"Keep Editing must preserve the open edit")
assert((try! Data(contentsOf:originalURL)) == originalData)
assert(!saveEditor.windowShouldClose(saveEditor.window!))
saveEditor.window!.endSheet(saveEditor.window!.attachedSheet!,returnCode:.alertFirstButtonReturn)
RunLoop.main.run(until:Date(timeIntervalSinceNow:0.4))
assert(!saveEditor.window!.isVisible && !saveEditor.canvas.hasUnsavedChanges)
assert(savedURL != originalURL && savedURL != nil)
assert((try! Data(contentsOf:originalURL)) == originalData,"Save a Copy must preserve the original bytes")
assert(FileManager.default.fileExists(atPath:savedURL!.path))
let replaceEditor = MarkupWindow(shot:CaptureController.Shot(url:originalURL,image:source)) { savedURL = $0.url }
drawIn(replaceEditor)
assert(!replaceEditor.windowShouldClose(replaceEditor.window!))
replaceEditor.window!.endSheet(replaceEditor.window!.attachedSheet!,returnCode:.alertSecondButtonReturn)
RunLoop.main.run(until:Date(timeIntervalSinceNow:0.4))
assert(!replaceEditor.window!.isVisible)
assert(savedURL == originalURL)
assert((try! Data(contentsOf:originalURL)) != originalData,"Replace must write the edited image to the original file")
print("Close/save checks passed: dirty prompt, all four choices, Keep Editing, Save Copy, and Replace Original.")

let afterReplace = try Data(contentsOf:originalURL)
let discardEditor = MarkupWindow(shot:CaptureController.Shot(url:originalURL,image:source)) { _ in assertionFailure("Discard must not save") }
drawIn(discardEditor)
assert(!discardEditor.windowShouldClose(discardEditor.window!))
discardEditor.window!.endSheet(discardEditor.window!.attachedSheet!,returnCode:.alertThirdButtonReturn)
RunLoop.main.run(until:Date(timeIntervalSinceNow:0.4))
assert(!discardEditor.window!.isVisible && (try! Data(contentsOf:originalURL)) == afterReplace)
let quitEditor = MarkupWindow(shot:CaptureController.Shot(url:originalURL,image:source)) { _ in }
drawIn(quitEditor)
var quitAllowed:Bool?
MarkupWindow.reviewBeforeQuitting { quitAllowed = $0 }
quitEditor.window!.endSheet(quitEditor.window!.attachedSheet!,returnCode:NSApplication.ModalResponse(rawValue:NSApplication.ModalResponse.alertFirstButtonReturn.rawValue+3))
RunLoop.main.run(until:Date(timeIntervalSinceNow:0.4))
assert(quitAllowed == false && quitEditor.window!.isVisible && quitEditor.canvas.hasUnsavedChanges)
MarkupWindow.reviewBeforeQuitting { quitAllowed = $0 }
quitEditor.window!.endSheet(quitEditor.window!.attachedSheet!,returnCode:.alertThirdButtonReturn)
RunLoop.main.run(until:Date(timeIntervalSinceNow:0.4))
assert(quitAllowed == true && !MarkupWindow.hasUnsavedEditors)
print("Native save-sheet checks passed for Save Copy, Replace, Discard, Keep Editing, and app-quit cancellation.")
