import AppKit
import ApplicationServices
import ImageIO
import SmarterShotCore

/// Uses the current tab's DevTools command, never a second browser/profile or a URL reload.
@MainActor enum ChromePageCapture {
    private static var task:Task<Void,Never>?
    static var isRunning:Bool { task != nil }
    static func cancelAndWait() async { let pending=task;pending?.cancel();await pending?.value }
    static func isChrome(windowID:CGWindowID)->Bool { owner(windowID).flatMap { NSRunningApplication(processIdentifier:$0)?.bundleIdentifier } == "com.google.Chrome" }
    fileprivate static func owner(_ id:CGWindowID)->pid_t? {
        (CGWindowListCopyWindowInfo(.optionIncludingWindow,id) as? [[String:Any]])?.first?[kCGWindowOwnerPID as String] as? pid_t
    }
    static func start(windowID:CGWindowID,frame:CGRect,completion:@escaping(CaptureController.Shot?)->Void) {
        guard !isRunning,!ScrollCapture.isRunning else { completion(nil);return }
        guard isChrome(windowID:windowID),AXIsProcessTrusted() else {
            showError("Chrome Full Page needs Google Chrome and SmarterShot’s Accessibility access. Enable it in System Settings → Privacy & Security → Accessibility, then try again.");completion(nil);return
        }
        let progress=ChromeCaptureProgress(frame:frame)
        progress.cancel={ task?.cancel() }
        task=Task {
            defer { progress.finish();task=nil }
            do {
                let driver=try ChromeCommandDriver(windowID:windowID,frame:frame)
                let data=try await ChromeCaptureEngine.capture(driver:.init(
                    prepare:{try await driver.prepare()},invoke:{try await driver.invoke()},
                    image:{try driver.freshImage(after:$0)},cleanup:{await driver.cleanup()}))
                try Task.checkCancellation()
                let raw=CaptureController.uniqueDestination(ext:"png")
                try await Task.detached { try data.write(to:raw,options:.atomic) }.value
                if Task.isCancelled { try? FileManager.default.removeItem(at:raw);throw CancellationError() }
                let app="Google Chrome"
                let saved=CaptureSourceContext.storeCapture(at:raw,appName:app,organizeByApp:ShortcutStore.organizeScreenshotsByApp)
                CaptureSourceContext.write(app,to:saved)
                progress.finish()
                SoundPlayer.play(ShortcutStore.soundName)
                completion(.init(url:saved,image:NSImage(data:data) ?? NSImage(),sourceAppName:app))
                if let notice=driver.cleanupNotice { showError("The screenshot was saved. " + notice) }
            } catch is CancellationError { progress.finish();completion(nil) }
            catch { progress.finish();showError(error.localizedDescription + " If Developer Tools opened and remains visible, close it manually when finished.");completion(nil) }
        }
    }
    private static func showError(_ text:String) {
        let alert=NSAlert();alert.messageText="Chrome Full Page";alert.informativeText=text
        alert.addButton(withTitle:"OK");NSApp.activate(ignoringOtherApps:true);alert.runModal()
    }
}

@MainActor private final class ChromeCommandDriver {
    let pid:pid_t,app:AXUIElement,window:AXUIElement
    private var pageURL:String
    private let page:AXUIElement
    private(set) var cleanupNotice:String?
    private var openedTools=false
    private var tools:AXUIElement?
    private var commandInput:AXUIElement?
    private let command="Capture full size screenshot"
    init(windowID:CGWindowID,frame:CGRect) throws {
        guard let pid=ChromePageCapture.owner(windowID),let running=NSRunningApplication(processIdentifier:pid),running.bundleIdentifier == "com.google.Chrome" else { throw ChromeCaptureError.message("The selected Chrome window is no longer available.") }
        self.pid=pid;app=AXUIElementCreateApplication(pid)
        let windows=Self.value(app,kAXWindowsAttribute) as? [AXUIElement] ?? []
        guard let window=windows.first(where:{ Self.rect($0).map { abs($0.minX-frame.minX)<3 && abs($0.minY-frame.minY)<3 && abs($0.width-frame.width)<3 && abs($0.height-frame.height)<3 } ?? false }) else { throw ChromeCaptureError.message("Chrome’s selected window couldn’t be verified. Try Scroll Capture instead.") }
        self.window=window
        guard let page=Self.pageElement(in:window) else { throw ChromeCaptureError.message("Chrome didn’t expose the current tab to Accessibility. Try Scroll Capture instead.") }
        self.page=page;pageURL=Self.url(page)
    }
    static func value(_ node:AXUIElement,_ key:String)->CFTypeRef? {
        AXUIElementSetMessagingTimeout(node,0.08)
        var result:CFTypeRef?
        guard AXUIElementCopyAttributeValue(node,key as CFString,&result) == .success else { return nil }
        return result
    }
    static func text(_ node:AXUIElement,_ key:String)->String { value(node,key) as? String ?? "" }
    static func nodes(_ root:AXUIElement)->[AXUIElement] {
        let deadline=Date().addingTimeInterval(0.25)
        var queue=[root],index=0
        while index<queue.count,index<700,Date()<deadline {
            let node=queue[index];index+=1
            queue.append(contentsOf:(value(node,kAXChildrenAttribute) as? [AXUIElement] ?? []).prefix(100))
        }
        return Array(queue.prefix(index))
    }
    static func url(_ node:AXUIElement)->String {
        if let url=value(node,kAXURLAttribute) as? URL { return url.absoluteString }
        return text(node,kAXURLAttribute)
    }
    static func isTools(_ node:AXUIElement)->Bool {
        let url=url(node)
        return text(node,kAXRoleAttribute) == "AXWebArea" && (url.hasPrefix("devtools://") || url.hasPrefix("chrome-devtools://"))
    }
    static func pageElement(in window:AXUIElement)->AXUIElement? {
        nodes(window).first { text($0,kAXRoleAttribute)=="AXWebArea" && !isTools($0) && !url($0).isEmpty }
    }
    static func rect(_ node:AXUIElement)->CGRect? {
        guard let p=value(node,kAXPositionAttribute),let s=value(node,kAXSizeAttribute),CFGetTypeID(p)==AXValueGetTypeID(),CFGetTypeID(s)==AXValueGetTypeID() else { return nil }
        var point=CGPoint.zero,size=CGSize.zero
        guard AXValueGetValue(p as! AXValue,.cgPoint,&point),AXValueGetValue(s as! AXValue,.cgSize,&size) else { return nil }
        return CGRect(origin:point,size:size)
    }
    func verify() throws {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let focused=Self.value(app,kAXFocusedWindowAttribute),CFEqual(focused,window),
              let current=Self.pageElement(in:window),CFEqual(current,page),Self.url(current)==pageURL else { throw ChromeCaptureError.message("The selected Chrome tab or window changed. Capture stopped; please try again without switching tabs.") }
    }
    private func key(_ code:CGKeyCode,flags:CGEventFlags = []) throws {
        try verify()
        for down in [true,false] {
            guard let event=CGEvent(keyboardEventSource:nil,virtualKey:code,keyDown:down) else { throw ChromeCaptureError.message("The Chrome command couldn’t be sent.") }
            event.flags=flags;event.postToPid(pid)
        }
    }
    private func waitFor(_ find:()->AXUIElement?) async throws -> AXUIElement {
        for _ in 0..<30 {
            try Task.checkCancellation();try verify()
            if let result=find() { return result }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        throw ChromeCaptureError.message("Chrome’s full-page command couldn’t be verified. This prototype needs English Chrome with docked Developer Tools. Try Scroll Capture instead.")
    }
    func prepare() async throws {
        let existing=Self.nodes(window).first(where:Self.isTools)
        // Never toggle or close an unrelated, undocked DevTools window.
        let windows=Self.value(app,kAXWindowsAttribute) as? [AXUIElement] ?? []
        guard !windows.contains(where:{ !CFEqual($0,window) && Self.nodes($0).contains(where:Self.isTools) }) else { throw ChromeCaptureError.message("Please close undocked Developer Tools before using Chrome Full Page. SmarterShot won’t change another tab’s tools.") }
        NSRunningApplication(processIdentifier:pid)?.activate(options:[])
        AXUIElementPerformAction(window,kAXRaiseAction as CFString)
        try await Task.sleep(nanoseconds:250_000_000)
        try verify()
        if let existing=existing { tools=existing }
        else {
            try key(34,flags:[.maskCommand,.maskAlternate]) // Cmd-Option-I
            // Mark only once the verified tools root actually appears.
            tools=try await waitFor { Self.nodes(self.window).first(where:Self.isTools) }
            openedTools=true
        }
        guard let tools=tools else { throw ChromeCaptureError.message("Developer Tools couldn’t be verified.") }
        // Cmd-Shift-P must originate in verified DevTools, never web content.
        func toolsHasFocus()->Bool {
            guard let focused=Self.value(app,kAXFocusedUIElementAttribute) else { return false }
            return Self.nodes(tools).contains { CFEqual($0,focused) }
        }
        if !toolsHasFocus() {
            let candidates=Self.nodes(tools).filter {
                [kAXRadioButtonRole,kAXTextFieldRole,kAXComboBoxRole].contains(Self.text($0,kAXRoleAttribute))
            }
            for node in candidates {
                if AXUIElementSetAttributeValue(node,kAXFocusedAttribute as CFString,kCFBooleanTrue) == .success,toolsHasFocus() { break }
            }
        }
        guard toolsHasFocus() else {
            throw ChromeCaptureError.message("Developer Tools couldn’t be focused safely. Click inside docked Developer Tools, then try again.")
        }
        try key(35,flags:[.maskCommand,.maskShift]) // Cmd-Shift-P
        let input=try await waitFor {
            Self.nodes(tools).first { node in
                let role=Self.text(node,kAXRoleAttribute)
                let hint=[kAXPlaceholderValueAttribute,kAXDescriptionAttribute,kAXTitleAttribute].map {Self.text(node,$0)}.joined(separator:" ").lowercased()
                return (role==kAXComboBoxRole || role==kAXTextFieldRole) && (hint.contains("command") || hint.contains("run") || hint.contains(">"))
            }
        }
        commandInput=input
        guard AXUIElementSetAttributeValue(input,kAXValueAttribute as CFString,command as CFString) == .success else { throw ChromeCaptureError.message("Chrome’s command search couldn’t be filled safely.") }
    }
    func invoke() async throws -> Int {
        guard let tools=tools else { throw ChromeCaptureError.message("Developer Tools is unavailable.") }
        let result=try await waitFor {
            Self.nodes(tools).first { node in
                let name=Self.text(node,kAXTitleAttribute).trimmingCharacters(in:.whitespacesAndNewlines)
                let description=Self.text(node,kAXDescriptionAttribute).trimmingCharacters(in:.whitespacesAndNewlines)
                return [name,description].contains(self.command) || [name,description].contains("Screenshot \(self.command)")
            }
        }
        try verify()
        let baseline=NSPasteboard.general.changeCount
        if AXUIElementPerformAction(result,kAXPressAction as CFString) != .success {
            // Some Chrome versions expose the exact option but no AXPress action.
            // Return is allowed only with the command search still focused and exact.
            guard let input=commandInput,let focused=Self.value(app,kAXFocusedUIElementAttribute),
                  CFEqual(focused,input),Self.text(input,kAXValueAttribute)==command else {
                throw ChromeCaptureError.message("Chrome’s full-page command couldn’t be activated safely.")
            }
            try key(36)
        }
        return baseline
    }
    func freshImage(after baseline:Int) throws -> Data? {
        try verify()
        let pb=NSPasteboard.general
        guard pb.changeCount != baseline else { return nil }
        guard let data=pb.data(forType:.png) else { return nil }
        guard data.count <= 160_000_000,let source=CGImageSourceCreateWithData(data as CFData,nil),
              let props=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
              let width=props[kCGImagePropertyPixelWidth] as? Int,let height=props[kCGImagePropertyPixelHeight] as? Int,
              width>0,height>0,width<=40_000_000/height else { throw ChromeCaptureError.message("Chrome’s image is too large or invalid. The limit is 40 megapixels.") }
        return data
    }
    func cleanup() async {
        guard openedTools else { return }
        cleanupNotice="Developer Tools was left open because SmarterShot couldn’t safely close it. You can close it manually."
        guard (try? verify()) != nil,let tools=tools,
              Self.nodes(window).contains(where:{CFEqual($0,tools)}) else { return }
        // A close button scoped to our verified DevTools document cannot close a page/tab.
        if let close=Self.nodes(tools).first(where:{Self.text($0,kAXRoleAttribute)==kAXButtonRole && [Self.text($0,kAXTitleAttribute),Self.text($0,kAXDescriptionAttribute)].contains("Close")}) {
            if AXUIElementPerformAction(close,kAXPressAction as CFString) == .success { cleanupNotice=nil }
        }
    }
}

@MainActor private final class ChromeCaptureProgress:NSObject {
    private let panel:NSPanel
    var cancel:(()->Void)?
    init(frame:CGRect) {
        panel=NSPanel(contentRect:NSRect(x:0,y:0,width:300,height:72),styleMask:[.nonactivatingPanel,.titled],backing:.buffered,defer:false)
        super.init()
        panel.title="Chrome Full Page";panel.level = .floating
        panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
        let label=NSTextField(labelWithString:"Capturing the rendered page…")
        label.frame=NSRect(x:14,y:40,width:275,height:18)
        let button=NSButton(title:"Cancel",target:self,action:#selector(stop))
        button.bezelStyle = .rounded;button.frame=NSRect(x:208,y:7,width:78,height:28)
        panel.contentView?.addSubview(label);panel.contentView?.addSubview(button)
        let screenHeight=NSScreen.screens.first?.frame.height ?? 900
        panel.setFrameOrigin(NSPoint(x:frame.maxX-316,y:screenHeight-frame.minY-125))
        panel.orderFrontRegardless()
    }
    @objc private func stop() { cancel?() }
    func finish() { panel.orderOut(nil) }
}
