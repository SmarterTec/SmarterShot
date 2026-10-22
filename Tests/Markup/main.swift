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
    canvas.mouseDown(with:event(.leftMouseDown,a.x,a.y))
    canvas.mouseDragged(with:event(.leftMouseDragged,b.x,b.y))
    canvas.mouseUp(with:event(.leftMouseUp,b.x,b.y))
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
canvas.mouseDown(with:send(.leftMouseDown,NSPoint(x:50,y:50)))
canvas.mouseDragged(with:send(.leftMouseDragged,NSPoint(x:250,y:200)))
canvas.mouseUp(with:send(.leftMouseUp,NSPoint(x:250,y:200)))
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
    canvas.togglePointEditing()
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
canvas.mouseDown(with:send(.leftMouseDown,NSPoint(x:50,y:50)))
canvas.mouseDragged(with:send(.leftMouseDragged,NSPoint(x:250,y:200)))
canvas.mouseUp(with:send(.leftMouseUp,NSPoint(x:250,y:200)))
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
let toolbar = root.subviews.compactMap { $0 as? NSStackView }.first {
    $0.arrangedSubviews.contains { ($0 as? NSButton)?.action == NSSelectorFromString("selectTool:") }
}!
let editedCanvas = root.subviews.compactMap { $0 as? NSScrollView }.first!.documentView as! MarkupCanvas
let toolButtons = toolbar.arrangedSubviews.compactMap { $0 as? NSButton }.filter { $0.action == NSSelectorFromString("selectTool:") }
let lineWidth = toolbar.arrangedSubviews.compactMap { $0 as? NSPopUpButton }.first!
let widthTitle = lineWidth.titleOfSelectedItem
for tool in MarkupCanvas.Tool.allCases {
    let button = toolButtons.first { $0.title == tool.rawValue }!
    assert(NSApp.sendAction(button.action!,to:button.target,from:button))
    assert(editedCanvas.tool == tool, "Toolbar must select the requested tool")
    assert(button.state == .on)
    assert(toolButtons.filter { $0.state == .on }.count == 1)
    assert(lineWidth.titleOfSelectedItem == widthTitle, "Tool changes must not affect line width")
}
// Completing the crop also switches the toolbar back to Select. Exercise
// that second callback through the real editor rather than the isolated canvas.
func editorEvent(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
    NSEvent.mouseEvent(with:type,location:editedCanvas.convert(point,to:nil),modifierFlags:[],timestamp:0,
        windowNumber:editor.window!.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
}
editedCanvas.mouseDown(with:editorEvent(.leftMouseDown,NSPoint(x:50,y:50)))
editedCanvas.mouseDragged(with:editorEvent(.leftMouseDragged,NSPoint(x:250,y:200)))
editedCanvas.mouseUp(with:editorEvent(.leftMouseUp,NSPoint(x:250,y:200)))
RunLoop.main.run(until:Date(timeIntervalSinceNow:0.4))
assert(editedCanvas.tool == .select)
assert(abs(editedCanvas.bounds.width-200)<0.01 && abs(editedCanvas.bounds.height-150)<0.01)
assert(toolButtons.first { $0.title == "Select" }!.state == .on)
editedCanvas.undoEdit()
RunLoop.main.run(until:Date(timeIntervalSinceNow:0.4))
assert(abs(editedCanvas.bounds.width-400)<0.01)
editor.close()
print("Toolbar checks passed: all tool buttons including Crop; unrelated controls untouched.")
