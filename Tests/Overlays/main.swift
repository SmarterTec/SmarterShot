import AppKit

enum CaptureController {
    struct Shot { let url:URL; let image:NSImage; var isVideo = false }
    static func copyToClipboard(_ shot:Shot) {}
    static func delete(_ shot:Shot) {}
}
final class PasteWatcher {
    static let shared = PasteWatcher()
    func forget(_ overlay:OverlayWindow) {}
    func noteCopied(overlay:OverlayWindow) {}
}
final class MarkupWindow {
    static var editing = false
    static func isEditing(url:URL)->Bool { editing }
    init(shot:CaptureController.Shot,onSave:@escaping(CaptureController.Shot)->Void) {}
}
final class PinnedWindow {
    init(image:NSImage,at:NSPoint) {}
}
let app = NSApplication.shared
func settle() { RunLoop.main.run(until:Date(timeIntervalSinceNow:0.4)) }
func add(_ index:Int) {
    let image = NSImage(size:NSSize(width:400,height:index % 2 == 0 ? 300 : 160))
    _ = OverlayWindow(shot:.init(url:URL(fileURLWithPath:"/tmp/overlay-test-\(index).png"),image:image),analyzeAutomatically:false)
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

// Suggestions are review-only until explicitly accepted; renaming preserves
// bytes, rejects collisions/traversal and leaves open markup paths untouched.
let fixtures = URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent(".build/overlay-tests/fixtures")
try FileManager.default.createDirectory(at:fixtures,withIntermediateDirectories:true)
let original = fixtures.appendingPathComponent("SmarterShot 2026-10-21 at 08.57.48.png")
let expected = fixtures.appendingPathComponent("2026-10-21 at 08.57.48 - Blender - rear-bumper.png")
try? FileManager.default.removeItem(at:expected)
try Data([1,2,3]).write(to:original)
let review = OverlayWindow(shot:.init(url:original,image:NSImage(size:NSSize(width:400,height:300))),analyzeAutomatically:false)
review.showSuggestion(ScreenshotAISuggestion(filename:"rear-bumper",description:"A rear bumper model.",appName:"Blender"))
assert(FileManager.default.fileExists(atPath:original.path) && !FileManager.default.fileExists(atPath:expected.path))
let cardViews = children(document.subviews.last!)
let nameField = cardViews.compactMap { $0 as? NSTextField }.first { $0.placeholderString == "Suggested filename" }!
let previewImage = cardViews.compactMap { $0 as? DraggableImageView }.first!
assert(previewImage.layer!.cornerRadius == 20 && previewImage.frame.minX == 0 && previewImage.frame.width == document.frame.width,
       "Edge-to-edge image shares the outer top corners")
assert(previewImage.fillsBounds && panel.allowsToolTipsWhenApplicationIsInactive)
let header = cardViews.compactMap { $0 as? NSTextField }.first { $0.stringValue == "A rear bumper model." }!
let body = cardViews.compactMap { $0 as? NSTextField }.first { $0.stringValue == original.lastPathComponent }!
assert(header.frame.minY > body.frame.maxY && header.font!.pointSize > body.font!.pointSize)
assert(body.frame.minY-nameField.frame.maxY <= 8,"Metadata spacing must be compact")
let actions = cardViews.compactMap { $0 as? NSButton }.filter { ["Copy image to clipboard","Show screenshot in Finder","Keep image floating above other windows","Edit and annotate screenshot"].contains($0.toolTip ?? "") }
assert(actions.count == 4 && actions.allSatisfy { $0.title.isEmpty && $0.frame.minY > previewImage.frame.minY })
MarkupWindow.editing = true
do { try review.useSuggestedFilename(); assertionFailure("Must not rename files in an open editor") } catch {}
MarkupWindow.editing = false
try Data([9]).write(to:expected)
do { try review.useSuggestedFilename(); assertionFailure("Must not overwrite an existing file") } catch {}
let existingBytes = try Data(contentsOf:expected)
assert(existingBytes == Data([9]))
try FileManager.default.removeItem(at:expected)
nameField.stringValue = "../outside.png"
do { try review.useSuggestedFilename(); assertionFailure("Must reject path traversal") } catch {}
nameField.stringValue = expected.lastPathComponent
try review.useSuggestedFilename()
assert(!FileManager.default.fileExists(atPath:original.path) && previewImage.fileURL == expected)
let renamedBytes = try Data(contentsOf:expected)
assert(renamedBytes == Data([1,2,3]))
review.dismiss(); settle()
print("Preview layout and filename checks passed: top controls, concentric corners, editable suggestions, explicit rename, collision/path/editor protection and updated drag URL.")

var analysisReplies:[CheckedContinuation<ScreenshotAISuggestion,Never>] = []
let delayed: @MainActor(URL) async throws -> ScreenshotAISuggestion = { _ in
    await withCheckedContinuation { analysisReplies.append($0) }
}
let queuedFirst = OverlayWindow(shot:.init(url:expected,image:NSImage(size:NSSize(width:400,height:300))),analyzer:delayed)
let queuedSecond = OverlayWindow(shot:.init(url:expected,image:NSImage(size:NSSize(width:400,height:300))),analyzer:delayed)
assert(OverlayWindow.stack.count == 2 && panel.isVisible,"Previews must appear before AI finishes")
settle()
assert(analysisReplies.count == 1,"Automatic model work should be serialized")
queuedFirst.dismiss()
analysisReplies[0].resume(returning:ScreenshotAISuggestion(filename:"stale",description:"Canceled result"))
settle()
assert(analysisReplies.count == 2)
analysisReplies[1].resume(returning:ScreenshotAISuggestion(filename:"reviewed",description:"Ready description"))
settle()
assert(!children(document).compactMap { $0 as? NSTextField }.contains { $0.stringValue == "Canceled result" })
assert(children(document).compactMap { $0 as? NSTextField }.contains { $0.stringValue == "Ready description" })
queuedSecond.dismiss(); settle()
print("Background analysis checks passed: immediate preview, serialized work, cancellation and no stale results.")
