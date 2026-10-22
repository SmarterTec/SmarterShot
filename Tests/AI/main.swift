import AppKit

@MainActor func drain() async { for _ in 0..<8 { await Task.yield() } }
@MainActor func checks() async throws {
    _ = NSApplication.shared
    let folder = URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent(".build/ai-tests/fixtures")
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    let rep = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:400,pixelsHigh:300,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    let bytes = rep.representation(using:.png,properties:[:])!
    let first = folder.appendingPathComponent("first.png"), second = folder.appendingPathComponent("second.png")
    try bytes.write(to:first); try bytes.write(to:second)
    let expectedSecond = ScreenshotAISuggestion(filename:"Second Image.png",description:"").suggestedFilename(for:second)
    var replies:[URL:CheckedContinuation<ScreenshotAISuggestion,Never>] = [:]
    let tester = AITesterWindow { url in await withCheckedContinuation { replies[url] = $0 } }
    tester.loadScreenshot(first); tester.analyze(); await drain()
    assert(tester.isAnalyzing && replies[first] != nil)
    tester.loadScreenshot(second); tester.analyze(); await drain()
    assert(tester.isAnalyzing && replies[second] != nil)
    replies[second]!.resume(returning:ScreenshotAISuggestion(filename:"Second Image.png",description:"The newer image."))
    await drain()
    assert(tester.suggestedFilename == expectedSecond && tester.suggestedDescription == "The newer image.")
    // Deliberately complete an analyzer that ignores cancellation. Its old
    // response must never replace the currently selected screenshot's results.
    replies[first]!.resume(returning:ScreenshotAISuggestion(filename:"wrong",description:"Outdated result"))
    await drain()
    assert(tester.suggestedFilename == expectedSecond)
    tester.analyze(); await drain(); tester.windowWillClose(Notification(name:NSWindow.willCloseNotification,object:tester.window))
    replies[second]!.resume(returning:ScreenshotAISuggestion(filename:"canceled",description:"Must not appear"))
    await drain()
    assert(!tester.isAnalyzing && tester.suggestedFilename == expectedSecond && tester.statusMessage.contains("Canceled"))
    let afterFirst = try Data(contentsOf:first), afterSecond = try Data(contentsOf:second)
    assert(afterFirst == bytes && afterSecond == bytes,"Preview testing must never modify source files")
    tester.window?.contentView?.layoutSubtreeIfNeeded()
    func views(_ v:NSView)->[NSView] { [v]+v.subviews.flatMap(views) }
    let fields = views(tester.window!.contentView!)
    assert(fields.compactMap { $0 as? NSTextField }.contains { $0.isEditable && $0.stringValue == expectedSecond })
    assert(fields.compactMap { $0 as? NSTextView }.contains { $0.isEditable && $0.string == "The newer image." })
    tester.close()
    let failing = AITesterWindow { _ in throw ScreenshotAIService.Failure.unavailable("On-device model unavailable") }
    failing.loadScreenshot(first); failing.analyze(); await drain()
    assert(!failing.isAnalyzing && failing.statusMessage.contains("On-device model unavailable"))
    assert(failing.suggestedFilename.isEmpty && failing.suggestedDescription.isEmpty)
    failing.close()
    do { _ = try await ScreenshotAIService.describe(URL(string:"https://example.com/screenshot.png")!); assertionFailure("Remote image URLs must be rejected") }
    catch ScreenshotAIService.Failure.invalidImage {}
    assert(ScreenshotAISuggestion(filename:"../../A:B/C.PNG",description:" a\n b ").filenameStem == "a-b-c")
    let capture = URL(fileURLWithPath:"/tmp/SmarterShot 2026-10-21 at 08.57.48.PNG")
    let named = ScreenshotAISuggestion(filename:"rear-bumper",description:"",appName:"Blender")
    assert(named.suggestedFilename(for:capture) == "2026-10-21 at 08.57.48 - Blender - rear-bumper.png")
    assert(ScreenshotAISuggestion(filename:"rear-bumper",description:"").suggestedFilename(for:capture)
        == "2026-10-21 at 08.57.48 - rear-bumper.png")
    assert(ScreenshotAISuggestion(filename:"blender-rear-bumper",description:"",appName:"Blender").suggestedFilename(for:capture)
        == "2026-10-21 at 08.57.48 - Blender - rear-bumper.png")
    assert(named.suggestedFilename(for:capture,sourceAppName:"Safari")
        == "2026-10-21 at 08.57.48 - Safari - rear-bumper.png", "Captured app must override the model")
    assert(named.suggestedFilename(for:capture,sourceAppName:"")
        == "2026-10-21 at 08.57.48 - rear-bumper.png", "Unknown captured app must not become an AI guess")
    let contextURL = folder.appendingPathComponent("context.png")
    try? FileManager.default.removeItem(at:contextURL)
    try bytes.write(to:contextURL)
    assert(CaptureSourceContext.read(from:contextURL) == nil)
    CaptureSourceContext.write("Blender",to:contextURL)
    assert(CaptureSourceContext.read(from:contextURL) == "Blender")
    CaptureSourceContext.write("",to:contextURL)
    assert(CaptureSourceContext.read(from:contextURL) == "")
    let windows:[[String:Any]] = [
        [kCGWindowLayer as String:0,kCGWindowOwnerPID as String:Int32(-1),kCGWindowOwnerName as String:"Safari",
         kCGWindowBounds as String:CGRect(x:0,y:0,width:100,height:100).dictionaryRepresentation],
        [kCGWindowLayer as String:0,kCGWindowOwnerPID as String:Int32(-2),kCGWindowOwnerName as String:"Blender",
         kCGWindowBounds as String:CGRect(x:100,y:0,width:100,height:100).dictionaryRepresentation]
    ]
    assert(CaptureSourceContext.applicationAtCenter(of:CGRect(x:120,y:20,width:40,height:40),in:windows,ownPID:42) == "Blender")
    assert(CaptureSourceContext.applicationAtCenter(of:CGRect(x:20,y:20,width:40,height:40),in:windows,ownPID:42) == "Safari")
    assert(CaptureSourceContext.applicationAtCenter(of:CGRect(x:20,y:20,width:40,height:40),in:windows,ownPID:-1) == nil)
    let storage = folder.appendingPathComponent("grouping-"+UUID().uuidString,isDirectory:true)
    try FileManager.default.createDirectory(at:storage,withIntermediateDirectories:true)
    let fresh = storage.appendingPathComponent("SmarterShot 2026-10-22 at 15.00.00.png")
    try bytes.write(to:fresh)
    let flat = CaptureSourceContext.storeCapture(at:fresh,appName:"Blender",organizeByApp:false)
    assert(flat.deletingLastPathComponent() == storage && flat.lastPathComponent.contains("Blender"))
    assert(!FileManager.default.fileExists(atPath:storage.appendingPathComponent("Blender").path))
    try bytes.write(to:fresh)
    let grouped = CaptureSourceContext.storeCapture(at:fresh,appName:"Blender",organizeByApp:true)
    assert(grouped.deletingLastPathComponent().lastPathComponent == "Blender")
    let groupedBytes = try Data(contentsOf:grouped); assert(groupedBytes == bytes)
    try bytes.write(to:fresh)
    let collision = CaptureSourceContext.storeCapture(at:fresh,appName:"Blender",organizeByApp:true)
    assert(collision != grouped && collision.lastPathComponent.contains("(2)"))
    try bytes.write(to:fresh)
    let unknown = CaptureSourceContext.storeCapture(at:fresh,appName:"",organizeByApp:true)
    assert(unknown.deletingLastPathComponent().lastPathComponent == "Other")
    try bytes.write(to:fresh)
    let safe = CaptureSourceContext.storeCapture(at:fresh,appName:"../../Safari",organizeByApp:true)
    assert(safe.deletingLastPathComponent() == storage.appendingPathComponent("Safari",isDirectory:true))
    try Data([1]).write(to:storage.appendingPathComponent("Blocked"))
    try bytes.write(to:fresh)
    let fallback = CaptureSourceContext.storeCapture(at:fresh,appName:"Blocked",organizeByApp:true)
    assert(fallback.deletingLastPathComponent() == storage && FileManager.default.fileExists(atPath:fallback.path))
    assert(FileManager.default.fileExists(atPath:flat.path),"Changing the option must not move existing captures")
    let fileDate = try second.resourceValues(forKeys:[.creationDateKey]).creationDate!
    let formatter = DateFormatter(); formatter.locale = Locale(identifier:"en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
    assert(expectedSecond == formatter.string(from:fileDate) + " - second-image.png")
    // Exercise the actual local OCR pipeline on a different subject so this
    // cannot pass through a hard-coded correction for the bumper screenshot.
    let labelImage = NSImage(size:NSSize(width:900,height:240))
    labelImage.lockFocus()
    NSColor.white.setFill(); NSRect(x:0,y:0,width:900,height:240).fill()
    ("Selected object: bicycle front wheel" as NSString).draw(at:NSPoint(x:30,y:100),
        withAttributes:[.font:NSFont.systemFont(ofSize:36),.foregroundColor:NSColor.black])
    labelImage.unlockFocus()
    let labelURL = folder.appendingPathComponent("object-label.png")
    let labelRep = NSBitmapImageRep(data:labelImage.tiffRepresentation!)!
    try labelRep.representation(using:.png,properties:[:])!.write(to:labelURL)
    let localText = try await ScreenshotAIService.recognizedText(in:labelURL)
    assert(localText.lowercased().contains("bicycle front wheel"), "Local OCR should preserve visible subject labels")
    do { _ = try await ScreenshotAIService.recognizedText(in:URL(string:"https://example.com/image.png")!); assertionFailure("OCR must reject remote URLs") }
    catch ScreenshotAIService.Failure.invalidImage {}
    let canceledOCR = Task { try Task.checkCancellation(); return try await ScreenshotAIService.recognizedText(in:labelURL) }
    canceledOCR.cancel()
    do { _ = try await canceledOCR.value; assertionFailure("Canceled OCR must not return evidence") }
    catch is CancellationError {}
    print("AI tester checks passed: read-only previews, editable results, cancellation, stale-result rejection, unavailable model, and local files only.")
    if CommandLine.arguments.count == 2 {
        let url = URL(fileURLWithPath:CommandLine.arguments[1])
        let before = try Data(contentsOf:url)
        let suggestion = try await ScreenshotAIService.describe(url)
        let after = try Data(contentsOf:url)
        assert(after == before)
        print("On-device filename: \(suggestion.suggestedFilename(for:url))")
        print("On-device description: \(suggestion.description)")
    }
}
Task { @MainActor in
    do { try await checks(); exit(0) }
    catch { fputs("AI check failed: \(error)\n",stderr); exit(1) }
}
RunLoop.main.run()
