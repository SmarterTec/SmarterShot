import AppKit

enum CaptureController {
    struct Shot { let url:URL; let image:NSImage; var isVideo:Bool { false } }
    static func copyToClipboard(_ shot:Shot) {}
    static func delete(_ shot:Shot) {}
}
final class PasteWatcher {
    static let shared = PasteWatcher()
    func forget(_ overlay:OverlayWindow) {}
    func noteCopied(overlay:OverlayWindow) {}
}
final class MarkupWindow {
    init(shot:CaptureController.Shot,onSave:@escaping(CaptureController.Shot)->Void) {}
}
final class PinnedWindow {
    init(image:NSImage,at:NSPoint) {}
}
let app = NSApplication.shared
func settle() { RunLoop.main.run(until:Date(timeIntervalSinceNow:0.4)) }
func add(_ index:Int) {
    let image = NSImage(size:NSSize(width:400,height:index % 2 == 0 ? 300 : 160))
    _ = OverlayWindow(shot:.init(url:URL(fileURLWithPath:"/tmp/overlay-test-\(index).png"),image:image))
}
add(0); add(1); add(2)
settle()
let panel = app.windows.first { $0.title == "Screenshot Previews" }!
let scroll = panel.contentView as! NSScrollView
let document = scroll.documentView!
if #available(macOS 26.0, *) {
    let glass = document.subviews.first as! NSGlassEffectView
    assert(glass.style == .regular && glass.contentView != nil && glass.cornerRadius == 20)
    if #available(macOS 27.0, *) { assert(glass.effectIsInteractive) }
}
assert(!scroll.hasVerticalScroller && !scroll.hasHorizontalScroller)
let before = document.subviews[1].frame.minY
OverlayWindow.stack[0].dismiss()
settle()
assert(OverlayWindow.stack.count == 2 && document.subviews.count == 2)
assert(document.subviews[0].frame.minY == 0)
assert(document.subviews[0].frame.minY < before,"Cards above a removed item must fall down")
for i in 3..<14 { add(i) }
settle()
assert(OverlayWindow.stack.count == 13,"Overflow must never discard older previews")
let visible = NSScreen.main!.visibleFrame
assert(panel.frame.minY >= visible.minY && panel.frame.maxY <= visible.maxY)
assert(document.frame.height > scroll.contentView.bounds.height)
let maximum = document.frame.height-scroll.contentView.bounds.height
assert(abs(scroll.contentView.bounds.minY-maximum)<2,"Reveal newest capture in overflow")
scroll.contentView.scroll(to:.zero)
assert(abs(scroll.contentView.bounds.minY)<1,"Oldest preview must remain reachable")
scroll.contentView.scroll(to:NSPoint(x:0,y:maximum))
assert(abs(scroll.contentView.bounds.minY-maximum)<2)
scroll.contentView.scroll(to:NSPoint(x:0,y:maximum/2))
let beforeWheel = scroll.contentView.bounds.minY
let cgWheel = CGEvent(scrollWheelEvent2Source:nil,units:.line,wheelCount:1,wheel1:3,wheel2:0,wheel3:0)!
scroll.scrollWheel(with:NSEvent(cgEvent:cgWheel)!)
settle()
assert(scroll.contentView.bounds.minY != beforeWheel,"Wheel must scroll even with no scrollbar")
let middle = OverlayWindow.stack[5]
middle.dismiss(); middle.dismiss(); settle()
assert(OverlayWindow.stack.count == 12,"Dismiss must be idempotent")
for (i,card) in document.subviews.enumerated() where i>0 {
    assert(abs(card.frame.minY-document.subviews[i-1].frame.maxY-10)<1,"No gaps after removal")
}
// Drag cancellation restores the thumbnail; successful drops retire its card.
func children(_ view:NSView)->[NSView] { [view]+view.subviews.flatMap(children) }
let thumbnail = children(document.subviews[0]).compactMap { $0 as? DraggableImageView }.first!
thumbnail.onDragWillBegin?(); assert(document.subviews[0].isHidden)
thumbnail.onDragEnded?([]); assert(!document.subviews[0].isHidden)
thumbnail.onDragWillBegin?(); thumbnail.onDragEnded?(.copy); settle()
assert(OverlayWindow.stack.count == 11)
for overlay in OverlayWindow.stack { overlay.dismiss() }
settle()
assert(OverlayWindow.stack.isEmpty && document.subviews.isEmpty && !panel.isVisible)
add(20); settle()
assert(panel.isVisible && scroll.contentView.bounds.minY == 0)
OverlayWindow.stack[0].dismiss(); settle()
print("Overlay stack checks passed: animated gap closure, unlimited retained previews, bounded viewport, hidden scrollbars, full scroll range, drag cancel/drop, idempotent removal and empty/reopen.")
