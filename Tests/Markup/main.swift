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
let canvas = MarkupCanvas(image:source)
let window = NSWindow(contentRect:canvas.bounds,styleMask:[.borderless],backing:.buffered,defer:false)
window.contentView = canvas
func event(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat, clicks: Int = 1) -> NSEvent {
    NSEvent.mouseEvent(with:type,location:NSPoint(x:x,y:y),modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:clicks,pressure:1)!
}
func drag(_ tool: MarkupCanvas.Tool, _ a: NSPoint, _ b: NSPoint) {
    canvas.tool = tool
    if tool == .crop { canvas.startNewCrop() }
    canvas.mouseDown(with:event(.leftMouseDown,a.x,a.y))
    canvas.mouseDragged(with:event(.leftMouseDragged,b.x,b.y))
    canvas.mouseUp(with:event(.leftMouseUp,b.x,b.y))
    if tool == .crop { canvas.applyCrop() }
}
func bitmap() -> NSBitmapImageRep { NSBitmapImageRep(data:canvas.render()!.tiffRepresentation!)! }
func isBlue(_ x: Int, _ y: Int) -> Bool {
    let c = bitmap().colorAt(x:x,y:y)!.usingColorSpace(.deviceRGB)!
    return c.blueComponent > c.redComponent + 0.2
}
canvas.ink = .blue
// Image coordinate y=100 corresponds to bitmap row 200.
drag(.curve,NSPoint(x:40,y:100),NSPoint(x:360,y:100))
assert(isBlue(200,200), "Curve must render")
canvas.mouseDown(with:event(.leftMouseDown,200,100))
canvas.mouseDragged(with:event(.leftMouseDragged,200,180))
canvas.mouseUp(with:event(.leftMouseUp,200,180))
assert(isBlue(200,120), "Green handle must bend the curve")
canvas.mouseDown(with:event(.leftMouseDown,280,150,clicks:2))
canvas.mouseDragged(with:event(.leftMouseDragged,280,220))
canvas.mouseUp(with:event(.leftMouseUp,280,220))
assert(isBlue(280,80), "Added curve point must be draggable")
canvas.undoEdit()
assert(!isBlue(280,80), "Undo must remove the added point")
canvas.redoEdit()
assert(isBlue(280,80), "Redo must restore the point")
canvas.deleteSelection() // redo clears selection, leaving marks intact
let full = bitmap()
assert(full.pixelsWide == 400 && full.pixelsHigh == 300)
for tool in [MarkupCanvas.Tool.line,.arrow,.rectangle,.ellipse,.highlight,.sketch] {
    drag(tool,NSPoint(x:20,y:20),NSPoint(x:80,y:80))
    assert(canvas.render() != nil)
}
drag(.crop,NSPoint(x:50,y:50),NSPoint(x:250,y:200))
let cropped = bitmap()
assert(cropped.pixelsWide == 200 && cropped.pixelsHigh == 150,"Crop exports the selected pixel region")
canvas.undoEdit()
assert(bitmap().pixelsWide == 400,"Crop must be undoable")
print("Markup checks passed: curve bend, extra point, undo/redo, all drawing tools, resolution, crop.")

// The visible document must crop as well as the exported bitmap, and the
// viewport must center documents smaller than it in both dimensions.
let clip = MarkupClipView(frame:NSRect(x:0,y:0,width:300,height:200))
clip.documentView = NSView(frame:NSRect(x:0,y:0,width:100,height:80))
let centered = clip.constrainBoundsRect(NSRect(x:0,y:0,width:300,height:200))
assert(centered.origin == NSPoint(x:-100,y:-60), "Small documents must be centered")
let scroll = NSScrollView(frame:NSRect(x:0,y:0,width:600,height:450))
scroll.contentView = MarkupClipView()
scroll.allowsMagnification = true
scroll.minMagnification = 0.1
scroll.maxMagnification = 4
window.setContentSize(scroll.frame.size)
window.contentView = scroll
scroll.documentView = canvas
canvas.fitInViewport()
func send(_ type: NSEvent.EventType, _ p: NSPoint) -> NSEvent {
    let inWindow = canvas.convert(p,to:nil)
    return event(type,inWindow.x,inWindow.y)
}
canvas.tool = .crop
canvas.startNewCrop()
canvas.mouseDown(with:send(.leftMouseDown,NSPoint(x:50,y:50)))
canvas.mouseDragged(with:send(.leftMouseDragged,NSPoint(x:250,y:200)))
canvas.mouseUp(with:send(.leftMouseUp,NSPoint(x:250,y:200)))
canvas.applyCrop()
RunLoop.main.run(until:Date(timeIntervalSinceNow:0.4))
assert(abs(canvas.bounds.minX-50) < 0.01 && abs(canvas.bounds.minY-50) < 0.01 && abs(canvas.bounds.width-200) < 0.01 && abs(canvas.bounds.height-150) < 0.01, "Only the cropped region should be visible after animation")
assert(isBlue(150,20), "Cropping must preserve annotation alignment")
let viewport = scroll.contentView.bounds
assert(abs(viewport.midX-canvas.frame.midX) < 1 && abs(viewport.midY-canvas.frame.midY) < 1, "Crop must finish centered")
canvas.undoEdit()
RunLoop.main.run(until:Date(timeIntervalSinceNow:0.4))
assert(abs(canvas.bounds.width-400) < 0.01 && abs(canvas.bounds.height-300) < 0.01, "Undo must restore the entire visible image")
canvas.redoEdit()
RunLoop.main.run(until:Date(timeIntervalSinceNow:0.4))
assert(abs(canvas.bounds.width-200) < 0.01 && abs(canvas.bounds.height-150) < 0.01, "Redo must restore the visible crop")
print("Viewport checks passed: initial centering, animated crop, annotation alignment, undo/redo.")

// Sketch handles stay hidden until explicitly requested.
canvas.undoEdit()
RunLoop.main.run(until:Date(timeIntervalSinceNow:0.4))
canvas.tool = .sketch
canvas.mouseDown(with:send(.leftMouseDown,NSPoint(x:40,y:40)))
canvas.mouseDragged(with:send(.leftMouseDragged,NSPoint(x:100,y:100)))
canvas.mouseUp(with:send(.leftMouseUp,NSPoint(x:100,y:100)))
assert(!canvas.isEditingPoints, "Sketch must hide points by default")
canvas.togglePointEditing()
assert(canvas.isEditingPoints, "Edit Points must reveal sketch handles")
canvas.togglePointEditing()
assert(!canvas.isEditingPoints, "Edit Points must hide handles again")
for shape in [MarkupCanvas.Tool.rectangle, .ellipse] {
    canvas.tool = shape
    canvas.mouseDown(with:send(.leftMouseDown,NSPoint(x:100,y:100)))
    canvas.mouseDragged(with:send(.leftMouseDragged,NSPoint(x:300,y:200)))
    canvas.mouseUp(with:send(.leftMouseUp,NSPoint(x:300,y:200)))
    if !canvas.isEditingPoints { canvas.togglePointEditing() }
    assert(canvas.isEditingPoints)
    let point = shape == .rectangle ? NSPoint(x:200,y:100) : NSPoint(x:300,y:150)
    let inWindow = canvas.convert(point,to:nil)
    canvas.mouseDown(with:event(.leftMouseDown,inWindow.x,inWindow.y,clicks:2))
    let moved = NSPoint(x:point.x,y:point.y-30)
    canvas.mouseDragged(with:send(.leftMouseDragged,moved))
    canvas.mouseUp(with:send(.leftMouseUp,moved))
    assert(isBlue(Int(moved.x),300-Int(moved.y)), "New outline point must reshape the box/oval")
    canvas.undoEdit()
    canvas.redoEdit()
}
print("Outline checks passed: box and oval points, sketch Edit Points toggle.")

// Inline text immediately returns to Select, remains hittable after editing,
// and supports both formatting controls and the visible resize handle.
canvas.tool = .text
canvas.mouseDown(with:send(.leftMouseDown,NSPoint(x:120,y:120)))
assert(canvas.tool == .select, "Adding text must switch back to Select")
let field = canvas.subviews.compactMap { $0 as? NSTextField }.first!
field.stringValue = "Move me"
canvas.controlTextDidChange(Notification(name:NSControl.textDidChangeNotification,object:field))
canvas.mouseDown(with:send(.leftMouseDown,NSPoint(x:390,y:280)))
assert(canvas.subviews.compactMap { $0 as? NSTextField }.isEmpty, "Text must edit inline without a modal")
canvas.mouseDown(with:send(.leftMouseDown,NSPoint(x:125,y:130)))
canvas.mouseDragged(with:send(.leftMouseDragged,NSPoint(x:175,y:150)))
canvas.mouseUp(with:send(.leftMouseUp,NSPoint(x:175,y:150)))
canvas.setTextFamily("Helvetica")
canvas.setTextSize(32)
assert(canvas.selectedTextFamily == "Helvetica" && canvas.selectedTextSize == 32, "Selected text must accept formatting")
let font = NSFontManager.shared.font(withFamily:"Helvetica",traits:[],weight:5,size:32)!
let textSize = ("Move me" as NSString).size(withAttributes:[.font:font])
let corner = NSPoint(x:170+textSize.width,y:140+textSize.height)
canvas.mouseDown(with:send(.leftMouseDown,corner))
canvas.mouseDragged(with:send(.leftMouseDragged,NSPoint(x:170+2*textSize.width,y:140+2*textSize.height)))
canvas.mouseUp(with:send(.leftMouseUp,NSPoint(x:170+2*textSize.width,y:140+2*textSize.height)))
assert(abs(canvas.selectedTextSize-64)<0.01,"Text resize handle must change the font size")
canvas.ink = .red
canvas.restyleSelection()
assert(canvas.selectedColor == NSColor.red,"Selected text must accept color changes")
canvas.undoEdit()
canvas.redoEdit()
assert(canvas.render() != nil)
print("Text checks passed: inline editing, automatic Select, moving, font/size/color, resize, undo/redo.")

canvas.tool = .crop
canvas.startNewCrop()
canvas.mouseDown(with:send(.leftMouseDown,NSPoint(x:50,y:50)))
canvas.mouseDragged(with:send(.leftMouseDragged,NSPoint(x:250,y:200)))
canvas.mouseUp(with:send(.leftMouseUp,NSPoint(x:250,y:200)))
canvas.applyCrop()
RunLoop.main.run(until:Date(timeIntervalSinceNow:0.4))
let display = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:400,pixelsHigh:300,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:display)
NSColor.magenta.setFill(); NSRect(x:0,y:0,width:400,height:300).fill()
canvas.draw(canvas.bounds)
NSGraphicsContext.restoreGraphicsState()
let outside = display.colorAt(x:10,y:10)!.usingColorSpace(.deviceRGB)!
assert(outside.redComponent > 0.9 && outside.blueComponent > 0.9 && outside.greenComponent < 0.1, "Cropped image must not draw into the surrounding margins")
print("Display clipping check passed.")

// Exercise actual toolbar actions, not just the canvas model. NSPopUpButton is
// an NSButton subclass, so a tool-state update must not index it as a tool.
let editor = MarkupWindow(shot:CaptureController.Shot(url:URL(fileURLWithPath:"/tmp/markup-toolbar-test.png"),image:source)) { _ in }
let root = editor.window!.contentView!
let editedCanvas = editor.canvas
let toolButtons = editor.window!.toolbar!.items.filter { $0.itemIdentifier.rawValue.hasPrefix("tool.") }.compactMap { $0.view as? NSButton }
for tool in MarkupCanvas.Tool.allCases {
    let button = toolButtons.first { $0.tag == MarkupCanvas.Tool.allCases.firstIndex(of:tool)! }!
    assert(NSApp.sendAction(button.action!,to:button.target,from:button))
    assert(editedCanvas.tool == tool, "Toolbar must select the requested tool")
    assert(button.state == .on)
    assert(toolButtons.filter { $0.state == .on }.count == 1)
}
// Completing the crop also switches the toolbar back to Select. Exercise
// that second callback through the real editor rather than the isolated canvas.
func editorEvent(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
    NSEvent.mouseEvent(with:type,location:editedCanvas.convert(point,to:nil),modifierFlags:[],timestamp:0,
        windowNumber:editor.window!.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
}
editedCanvas.startNewCrop()
editedCanvas.mouseDown(with:editorEvent(.leftMouseDown,NSPoint(x:50,y:50)))
editedCanvas.mouseDragged(with:editorEvent(.leftMouseDragged,NSPoint(x:250,y:200)))
editedCanvas.mouseUp(with:editorEvent(.leftMouseUp,NSPoint(x:250,y:200)))
editedCanvas.applyCrop()
RunLoop.main.run(until:Date(timeIntervalSinceNow:0.4))
assert(editedCanvas.tool == .select)
assert(abs(editedCanvas.bounds.width-200)<0.01 && abs(editedCanvas.bounds.height-150)<0.01)
assert(toolButtons.first { $0.tag == 0 }!.state == .on)
editedCanvas.undoEdit()
RunLoop.main.run(until:Date(timeIntervalSinceNow:0.4))
assert(abs(editedCanvas.bounds.width-400)<0.01)
editor.close()
print("Toolbar checks passed: all tool buttons including Crop; unrelated controls untouched.")

// Point editing remains active across reselection, and Add Point works for
// open polylines (including arrows) as well as every closed/freehand outline.
for shape in [MarkupCanvas.Tool.line,.arrow,.rectangle,.ellipse,.curve,.sketch,.highlight] {
    let c = MarkupCanvas(image:source)
    let w = NSWindow(contentRect:c.bounds,styleMask:[.borderless],backing:.buffered,defer:false)
    w.contentView = c
    func e(_ type:NSEvent.EventType,_ p:NSPoint,clicks:Int=1) -> NSEvent {
        NSEvent.mouseEvent(with:type,location:c.convert(p,to:nil),modifierFlags:[],timestamp:0,windowNumber:w.windowNumber,context:nil,eventNumber:0,clickCount:clicks,pressure:1)!
    }
    c.tool = shape
    c.mouseDown(with:e(.leftMouseDown,NSPoint(x:40,y:60)))
    c.mouseDragged(with:e(.leftMouseDragged,NSPoint(x:340,y:220)))
    c.mouseUp(with:e(.leftMouseUp,NSPoint(x:340,y:220)))
    if !c.isEditingPoints { c.togglePointEditing() }
    assert(c.isEditingPoints)
    let point:NSPoint
    switch shape {
    case .rectangle,.highlight: point = NSPoint(x:180,y:60)
    case .ellipse: point = NSPoint(x:190+150*cos(CGFloat.pi/8),y:140+80*sin(CGFloat.pi/8))
    default: point = NSPoint(x:115,y:100)
    }
    // First select the edge without adding a point; editing must not turn off.
    c.mouseDown(with:e(.leftMouseDown,point))
    c.mouseUp(with:e(.leftMouseUp,point))
    assert(c.isEditingPoints,"Reselecting a line must preserve Edit Points")
    let before = c.selectionPointCount
    c.toggleAddingPoints()
    assert(c.isAddingPoints)
    c.mouseDown(with:e(.leftMouseDown,point))
    c.mouseUp(with:e(.leftMouseUp,point))
    assert(c.selectionPointCount == before+1,"Add Point must work for \(shape)")
    assert(c.isEditingPoints && c.isAddingPoints)
    let moved = NSPoint(x:point.x+5,y:point.y+20)
    c.mouseDown(with:e(.leftMouseDown,point))
    c.mouseDragged(with:e(.leftMouseDragged,moved))
    c.mouseUp(with:e(.leftMouseUp,moved))
    assert((0..<c.selectionPointCount).contains { c.selectedPoint(at:$0) == moved },"Added point must be draggable")
    c.undoEdit(); c.redoEdit()
    assert(c.render() != nil)
}
print("Persistent point-editing checks passed for lines, arrows, boxes, ovals, curves, sketches, and highlights.")

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
cropCanvas.setCropScale(2)
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
