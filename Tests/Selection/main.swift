import AppKit
import QuartzCore
import SmarterShotCore

// Isolate native event routing from external apps and privacy permissions.
enum CaptureController { static func log(_ text:String) {} }
enum ScrollCapture { @MainActor static func supports(windowID:CGWindowID,frame:CGRect) async -> Bool { true } }
enum WindowPicker {
    static func windowUnder(point:CGPoint,in:[[String:Any]],ownWindowNumbers:Set<Int>) -> (id:CGWindowID,cgRect:CGRect)? {
        (321,CGRect(x:100,y:100,width:700,height:500))
    }
}
let app=NSApplication.shared
app.setActivationPolicy(.prohibited)
func settle(_ duration:Double=0.05) { RunLoop.main.run(until:Date().addingTimeInterval(duration)) }
func picker()->NSWindow { app.windows.first { $0.title == "Select Window" && $0.isVisible }! }
func event(_ type:NSEvent.EventType, flags:NSEvent.ModifierFlags=[])->NSEvent {
    NSEvent.mouseEvent(with:type,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:picker().windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:0)!
}
var completed=0, full=0
SelectionOverlay.present(mode:.window) { target in if case .window(321,_) = target { completed += 1 } }
settle()
assert(!picker().contentView!.subviews.contains { $0 is NSButton },"Recording picker must have no full-page action")
picker().contentView!.mouseUp(with:event(.leftMouseUp))
assert(completed == 1)
SelectionOverlay.present(mode:.window,fullPage:{id,_ in assert(id == 321);full += 1}) { _ in completed += 1 }
settle()
let button=picker().contentView!.subviews.compactMap { $0 as? NSButton }.first!
assert(button.isEnabled && !button.isHidden && button.toolTip!.contains("Accessibility"))
let shimmer = button.layer!.sublayers!.compactMap { $0 as? CAGradientLayer }.first!
assert(!shimmer.isHidden)
assert(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || shimmer.animation(forKey:"discovery") != nil,"Full Page discovery shimmer must run unless Reduce Motion is enabled")
button.performClick(nil);settle(0.2)
assert(shimmer.animation(forKey:"discovery") == nil,"Discovery animation stops when picker closes")
assert(full == 1 && completed == 1,"Full Page button must not also perform visible-window capture")
SelectionOverlay.present(mode:.window,fullPage:{_,_ in full += 1}) { _ in completed += 1 }
settle()
picker().contentView!.mouseUp(with:event(.leftMouseUp,flags:.shift));settle(0.2)
assert(full == 2 && completed == 1,"Shift-click invokes only Full Page")
SelectionOverlay.present(mode:.window,fullPage:{_,_ in full += 1}) { _ in completed += 1 }
settle()
let view=picker().contentView!
let escape=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:picker().windowNumber,context:nil,characters:"\u{1b}",charactersIgnoringModifiers:"\u{1b}",isARepeat:false,keyCode:53)!
view.keyDown(with:escape);view.keyDown(with:escape)
assert(completed == 2 && full == 2,"Escape cancellation must complete once")
print("Native picker checks passed: recording unchanged, Full Page button, Shift-click, and idempotent Escape.")
