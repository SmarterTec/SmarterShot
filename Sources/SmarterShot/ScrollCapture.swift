import AppKit
import ApplicationServices
import ScreenCaptureKit
import SmarterShotCore

/// Extension-free capture. Only explicit Full Page requests may ask for AX access.
@MainActor enum ScrollCapture {
    enum Failure:LocalizedError {
        case message(String)
        var errorDescription:String? { if case .message(let text)=self { return text }; return nil }
    }
    private static var task:Task<Void,Never>?
    private static var progress:ScrollCaptureProgress?
    static var isRunning:Bool { task != nil }
    static func cancelAndWait() async { let current=task;current?.cancel();await current?.value }

    /// Read-only detection never requests permission or changes scroll position.
    static func supports(windowID:CGWindowID,frame:CGRect) async -> Bool {
        guard #available(macOS 15.2,*) else { return false }
        guard AXIsProcessTrusted() else { return true } // Explicit button explains how to enable access.
        return await Task.detached { (try? AXScrollTarget.find(windowID:windowID,windowFrame:frame)) != nil }.value
    }
    static func start(windowID:CGWindowID,frame:CGRect,completion:@escaping(CaptureController.Shot?)->Void) {
        guard !ChromePageCapture.isRunning else { completion(nil);return }
        guard task == nil else { progress?.showWindow(nil); return }
        guard #available(macOS 15.2,*) else { showError("Full Page capture needs macOS 15.2 or later.");completion(nil);return }
        guard AXIsProcessTrusted() else {
            let alert=NSAlert();alert.messageText="Enable Full Page capture"
            alert.informativeText="SmarterShot needs Accessibility access to find scrollable content, scroll it, and restore your position. Regular screenshots work without it. Enable SmarterShot in Accessibility (add it from Applications if needed), then choose Full Page again. No browser extension is needed."
            alert.addButton(withTitle:"Open Accessibility Settings");alert.addButton(withTitle:"Cancel")
            NSApp.activate(ignoringOtherApps:true)
            if alert.runModal() == .alertFirstButtonReturn,let url=URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
            completion(nil);return
        }
        let panel=ScrollCaptureProgress();progress=panel
        panel.place(over:frame)
        panel.onCancel={ task?.cancel() };panel.showWindow(nil);NSApp.activate(ignoringOtherApps:true)
        task=Task {
            var restoreUnverified=false,pointerUnrestored=false
            defer { panel.finish();progress=nil;task=nil }
            do {
                let target=try await Task.detached(priority:.userInitiated) { try AXScrollTarget.find(windowID:windowID,windowFrame:frame) }.value
                let (result,_) = try await ScrollCaptureEngine.restoring(restore: {
                    panel.restoring()
                    let restored = await Task.detached { target.restore() }.value
                    if !restored {
                        if target.scrollbar == nil { pointerUnrestored=true }
                        else { restoreUnverified=true }
                    }
                    return restored
                }, operation: {
                    try await capture(target:target,windowID:windowID,frame:frame,onRestoreFailure:{restoreUnverified=true}) { count in panel.update(count) }
                })
                try Task.checkCancellation()
                let raw=CaptureController.uniqueDestination(ext:"png")
                panel.saving()
                try await Task.detached(priority:.userInitiated) {
                    let bitmap=NSBitmapImageRep(cgImage:result)
                    guard let data=bitmap.representation(using:.png,properties:[:]) else { throw Failure.message("The captured page couldn’t be saved.") }
                    try data.write(to:raw,options:.atomic)
                }.value
                if Task.isCancelled { try? FileManager.default.removeItem(at:raw);throw CancellationError() }
                let app=CaptureSourceContext.applicationName(windowID:windowID) ?? ""
                let saved=CaptureSourceContext.storeCapture(at:raw,appName:app,organizeByApp:ShortcutStore.organizeScreenshotsByApp)
                CaptureSourceContext.write(app,to:saved)
                let image=NSImage(cgImage:result,size:NSSize(width:result.width,height:result.height))
                SoundPlayer.play(ShortcutStore.soundName)
                panel.finish()
                completion(CaptureController.Shot(url:saved,image:image,sourceAppName:app))
                if restoreUnverified { showError("The capture was saved, but SmarterShot couldn’t verify the restored scroll position. Please check the selected window.") }
                else if pointerUnrestored { showError("The capture was saved and the page restored, but the pointer could not be returned to its starting position.") }
            } catch is CancellationError {
                panel.finish();completion(nil)
                if restoreUnverified { showError("Capture canceled. SmarterShot couldn’t verify the restored scroll position; please check the selected window.") }
            }
            catch { panel.finish();showError(error.localizedDescription);completion(nil) }
        }
    }
    private static func showError(_ text:String) {
        progress?.finish()
        let alert=NSAlert();alert.messageText="Full Page Capture";alert.informativeText=text;alert.addButton(withTitle:"OK")
        NSApp.activate(ignoringOtherApps:true);alert.runModal()
    }
    @available(macOS 15.2,*)
    private static func capture(target:AXScrollTarget,windowID:CGWindowID,frame:CGRect,onRestoreFailure:@escaping()->Void,update:(Int)->Void) async throws -> CGImage {
        let available=try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:false)
        guard let window=available.windows.first(where:{$0.windowID==windowID}) else { throw Failure.message("The selected window is no longer available.") }
        let filter=SCContentFilter(desktopIndependentWindow:window)
        let scale=NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        let config=SCStreamConfiguration();config.width=Int(frame.width*scale);config.height=Int(frame.height*scale)
        config.showsCursor=false;config.ignoreShadowsSingleWindow=true
        let viewport=target.viewport.intersection(frame)
        guard viewport.width>100,viewport.height>100 else { throw Failure.message("The scrollable area is too small to capture.") }
        func snapshot() async throws -> CGImage {
            try Task.checkCancellation()
            guard let list=CGWindowListCopyWindowInfo(.optionIncludingWindow,windowID) as? [[String:Any]],
                  let bounds=list.first?[kCGWindowBounds as String] as? [String:Any],
                  let current=CGRect(dictionaryRepresentation:bounds as CFDictionary),
                  abs(current.minX-frame.minX)<2,abs(current.minY-frame.minY)<2,
                  abs(current.width-frame.width)<2,abs(current.height-frame.height)<2 else { throw Failure.message("The window moved or resized. Please try Full Page again with the window in place.") }
            let image=try await SCScreenshotManager.captureImage(contentFilter:filter,configuration:config)
            let sx=CGFloat(image.width)/frame.width,sy=CGFloat(image.height)/frame.height
            let crop=CGRect(x:(viewport.minX-frame.minX)*sx,y:(viewport.minY-frame.minY)*sy,width:viewport.width*sx,height:viewport.height*sy).integral
            guard let result=image.cropping(to:crop) else { throw Failure.message("The scrollable image couldn’t be captured.") }
            return result
        }
        if target.scrollbar == nil {
            await target.prepareForWheel()
            progress?.window?.orderFrontRegardless()
            progress?.window?.displayIfNeeded()
            return try await ScrollCaptureEngine.captureRelative(snapshot:snapshot,
                scroll: { pixels in try await Task.detached { try target.scrollPixels(pixels) }.value },
                pixelsPerPoint:Double(scale),willRestore:{progress?.restoring()},onRestoreFailure:onRestoreFailure,update:update)
        }
        return try await ScrollCaptureEngine.capture(snapshot:snapshot,
            setPosition: { value in try await Task.detached { try target.setPosition(value) }.value },
            positionValue: { try await Task.detached { try target.position() }.value },update:update)
    }
}

/// AX operations run away from the main thread, with bounded tree traversal.
private final class AXScrollTarget:@unchecked Sendable {
    let scrollbar:AXUIElement?,viewport:CGRect,original:Double,min:Double,max:Double
    let pid:Int32,windowID:CGWindowID
    let selectedWindow:AXUIElement
    private var originalPointer:CGPoint?
    init(scrollbar:AXUIElement?,viewport:CGRect,original:Double,min:Double,max:Double,pid:Int32,windowID:CGWindowID,selectedWindow:AXUIElement) { self.scrollbar=scrollbar;self.viewport=viewport;self.original=original;self.min=min;self.max=max;self.pid=pid;self.windowID=windowID;self.selectedWindow=selectedWindow }
    static func attribute(_ element:AXUIElement,_ name:CFString)->CFTypeRef? { AXUIElementSetMessagingTimeout(element,0.15);var value:CFTypeRef?;guard AXUIElementCopyAttributeValue(element,name,&value) == .success else { return nil };return value }
    static func rect(_ element:AXUIElement)->CGRect? {
        guard let p=attribute(element,kAXPositionAttribute as CFString),let s=attribute(element,kAXSizeAttribute as CFString),CFGetTypeID(p)==AXValueGetTypeID(),CFGetTypeID(s)==AXValueGetTypeID() else { return nil }
        var point=CGPoint.zero,size=CGSize.zero
        guard AXValueGetValue(p as! AXValue,.cgPoint,&point),AXValueGetValue(s as! AXValue,.cgSize,&size) else { return nil };return CGRect(origin:point,size:size)
    }
    static func find(windowID:CGWindowID,windowFrame:CGRect) throws -> AXScrollTarget {
        guard let list=CGWindowListCopyWindowInfo(.optionIncludingWindow,windowID) as? [[String:Any]],let pid=list.first?[kCGWindowOwnerPID as String] as? Int32 else { throw ScrollCapture.Failure.message("The selected window is no longer available.") }
        let app=AXUIElementCreateApplication(pid)
        let windows=attribute(app,kAXWindowsAttribute as CFString) as? [AXUIElement] ?? []
        guard let window=windows.first(where:{ guard let r=rect($0) else { return false };return abs(r.minX-windowFrame.minX)<4 && abs(r.minY-windowFrame.minY)<4 && abs(r.width-windowFrame.width)<4 && abs(r.height-windowFrame.height)<4 }) else { throw ScrollCapture.Failure.message("This app does not expose its selected window to Accessibility.") }
        var queue:[(AXUIElement,Int)]=[(window,0)],index=0,best:AXScrollTarget?,relative:AXScrollTarget?
        let started=Date()
        while index<queue.count && index<600 && Date().timeIntervalSince(started)<2 {
            try Task.checkCancellation()
            let (node,depth)=queue[index];index += 1
            let role=attribute(node,kAXRoleAttribute as CFString) as? String
            if role == kAXScrollAreaRole as String, let area=rect(node), area.intersection(windowFrame).width>100, area.intersection(windowFrame).height>100 {
                let viewport=area.intersection(windowFrame)
                if relative == nil || viewport.width*viewport.height>relative!.viewport.width*relative!.viewport.height {
                    relative=AXScrollTarget(scrollbar:nil,viewport:viewport,original:0,min:0,max:1,pid:pid,windowID:windowID,selectedWindow:window)
                }
            }
            if role==kAXScrollAreaRole as String,let area=rect(node),area.intersection(windowFrame).width>100,area.intersection(windowFrame).height>100,
               let raw=attribute(node,kAXVerticalScrollBarAttribute as CFString),CFGetTypeID(raw)==AXUIElementGetTypeID() {
                let bar=raw as! AXUIElement
                var settable=DarwinBoolean(false)
                if AXUIElementIsAttributeSettable(bar,kAXValueAttribute as CFString,&settable) == .success,settable.boolValue,
                   let value=attribute(bar,kAXValueAttribute as CFString) as? Double {
                    let minimum=attribute(bar,kAXMinValueAttribute as CFString) as? Double ?? 0,maximum=attribute(bar,kAXMaxValueAttribute as CFString) as? Double ?? 1
                    if maximum>minimum,(attribute(bar,kAXEnabledAttribute as CFString) as? Bool) != false {
                        var viewport=area.intersection(windowFrame)
                        if let barRect=rect(bar),barRect.minX>viewport.midX,barRect.width<40 { viewport.size.width=Swift.min(viewport.width,barRect.minX-viewport.minX) }
                        let candidate=AXScrollTarget(scrollbar:bar,viewport:viewport,original:value,min:minimum,max:maximum,pid:pid,windowID:windowID,selectedWindow:window)
                        if best==nil || viewport.width*viewport.height>best!.viewport.width*best!.viewport.height { best=candidate }
                        continue
                    }
                }
            }
            if depth<15,let children=attribute(node,kAXChildrenAttribute as CFString) as? [AXUIElement] { queue.append(contentsOf:children.prefix(100).map { ($0,depth+1) }) }
        }
        guard let target=best ?? relative else { throw ScrollCapture.Failure.message("No supported scrollable area was found in this window.") };return target
    }
    func position() throws -> Double {
        guard let scrollbar=scrollbar,let value=Self.attribute(scrollbar,kAXValueAttribute as CFString) as? Double,value.isFinite else { throw ScrollCapture.Failure.message("The page’s scroll position is no longer available.") };return (value-min)/(max-min)
    }
    func setPosition(_ fraction:Double) throws {
        guard let scrollbar=scrollbar else { throw ScrollCapture.Failure.message("No adjustable scrollbar is available.") }
        let value=min+(max-min)*Swift.max(0,Swift.min(1,fraction))
        guard AXUIElementSetAttributeValue(scrollbar,kAXValueAttribute as CFString,NSNumber(value:value) as CFNumber) == .success else { throw ScrollCapture.Failure.message("This app did not allow its scroll position to be changed.") }
    }
    @MainActor func prepareForWheel() async {
        NSRunningApplication(processIdentifier:pid)?.activate(options:[.activateIgnoringOtherApps])
        _ = await Task.detached { AXUIElementPerformAction(self.selectedWindow,kAXRaiseAction as CFString) }.value
        try? await Task.sleep(nanoseconds:400_000_000)
        originalPointer=CGEvent(source:nil)?.location
        CGWarpMouseCursorPosition(CGPoint(x:viewport.midX,y:viewport.midY))
    }
    func scrollPixels(_ pixels:Int) throws {
        let point=CGPoint(x:viewport.midX,y:viewport.midY)
        let windows=CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []
        let own=ProcessInfo.processInfo.processIdentifier
        let first=windows.first { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? Int32) != own,
                  let raw=info[kCGWindowBounds as String] as? [String:Any],let rect=CGRect(dictionaryRepresentation:raw as CFDictionary) else { return false }
            return rect.contains(point)
        }
        guard first?[kCGWindowNumber as String] as? CGWindowID == windowID else { throw ScrollCapture.Failure.message("The selected window is covered. Keep it visible while capturing.") }
        guard let event=CGEvent(scrollWheelEvent2Source:nil,units:.pixel,wheelCount:1,wheel1:Int32(clamping:-pixels),wheel2:0,wheel3:0) else { throw ScrollCapture.Failure.message("The page could not be scrolled.") }
        event.location=CGPoint(x:viewport.midX,y:viewport.midY)
        event.setIntegerValueField(.scrollWheelEventIsContinuous,value:1)
        event.flags=[]
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer,value:Int64(windowID))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent,value:Int64(windowID))
        event.post(tap:.cghidEventTap)
    }
    func restore()->Bool {
        guard let scrollbar=scrollbar else {
            if let point=originalPointer { return CGWarpMouseCursorPosition(point) == .success }
            return true
        } // Relative engine restores the document; this restores the pointer.
        guard AXUIElementSetAttributeValue(scrollbar,kAXValueAttribute as CFString,NSNumber(value:original) as CFNumber) == .success else { return false }
        for _ in 0..<12 {
            if let value=Self.attribute(scrollbar,kAXValueAttribute as CFString) as? Double,
               abs(value-original) <= (max-min)*0.00001 { return true }
            Thread.sleep(forTimeInterval:0.04)
        }
        return false
    }
}

private final class ScrollCaptureProgress:NSWindowController,NSWindowDelegate {
    var onCancel:(()->Void)?
    private let label=NSTextField(labelWithString:"Preparing page capture…")
    private var escapeMonitor:Any?
    init() {
        let panel=NSPanel(contentRect:NSRect(x:0,y:0,width:340,height:130),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        super.init(window:panel);panel.title="Full Page Capture";panel.isReleasedWhenClosed=false;panel.delegate=self;panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        let root=NSView(frame:panel.contentView!.bounds)
        label.frame=NSRect(x:20,y:77,width:300,height:20);label.font = .systemFont(ofSize:13);root.addSubview(label)
        let spinner=NSProgressIndicator(frame:NSRect(x:20,y:35,width:20,height:20));spinner.style = .spinning;spinner.startAnimation(nil);root.addSubview(spinner)
        let cancel=NSButton(title:"Cancel",target:self,action:#selector(cancel));cancel.bezelStyle = .rounded;cancel.keyEquivalent="\u{1b}";cancel.frame=NSRect(x:236,y:24,width:84,height:32);root.addSubview(cancel)
        panel.contentView=root;panel.center()
        escapeMonitor=NSEvent.addGlobalMonitorForEvents(matching:.keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.cancel() }
        }
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) not used") }
    func place(over frame:CGRect) {
        guard let window=window else { return }
        let height=(NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first)?.frame.height ?? 0
        window.setFrameOrigin(NSPoint(x:frame.maxX-window.frame.width-20,y:height-frame.minY-window.frame.height-20))
    }
    private func status(_ text:String) { label.stringValue=text;window?.displayIfNeeded() }
    func update(_ count:Int) { status("Capturing page · \(count) \(count == 1 ? "section" : "sections")") }
    func restoring() { status("Restoring scroll position…") }
    func saving() { status("Saving capture…") }
    @objc private func cancel() { restoring();onCancel?() }
    func windowShouldClose(_ sender:NSWindow)->Bool { cancel();return false }
    func finish() {
        if let monitor=escapeMonitor { NSEvent.removeMonitor(monitor);escapeMonitor=nil }
        window?.orderOut(nil)
    }
    deinit { if let monitor=escapeMonitor { NSEvent.removeMonitor(monitor) } }
}
