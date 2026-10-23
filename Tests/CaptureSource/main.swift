import AppKit

@main struct Checks {
    static func main() throws {
        // File/metadata checks only: no NSApplication, windows, capture or model calls.
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("SmarterShot-source-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let bytes=Data([1,2,3,4])
        let raw=root.appendingPathComponent("SmarterShot 2026-10-22 at 18.00.00.png")
        for unknown in [nil,"","  ","../"] as [String?] {
            try bytes.write(to:raw)
            let saved=CaptureSourceContext.storeCapture(at:raw,appName:unknown,organizeByApp:true)
            precondition(saved==raw)
            let savedBytes=try Data(contentsOf:saved)
            precondition(savedBytes==bytes)
            precondition(!FileManager.default.fileExists(atPath:root.appendingPathComponent("Other").path))
        }
        print("PASS nil/empty/invalid app remains saved in root; no Other folder")
        CaptureSourceContext.write("",to:raw)
        precondition(CaptureSourceContext.read(from:raw)=="")
        let suggestion=ScreenshotAISuggestion(filename:"blender-bumper",description:"",appName:"Blender")
        precondition(suggestion.suggestedFilename(for:raw,sourceAppName:CaptureSourceContext.read(from:raw)) == "2026-10-22 at 18.00.00 - bumper.png")
        print("PASS unknown-app metadata blocks model attribution in filename")
        let known=CaptureSourceContext.storeCapture(at:raw,appName:"Blender",organizeByApp:true)
        precondition(known.deletingLastPathComponent()==root.appendingPathComponent("Blender",isDirectory:true))
        let knownBytes=try Data(contentsOf:known)
        precondition(knownBytes==bytes)
        try bytes.write(to:raw)
        let collision=CaptureSourceContext.storeCapture(at:raw,appName:"Blender",organizeByApp:true)
        precondition(collision != known && collision.lastPathComponent.contains("(2)"))
        print("PASS known window app groups without overwriting existing captures")
        try bytes.write(to:raw)
        let flat=CaptureSourceContext.storeCapture(at:raw,appName:"Safari",organizeByApp:false)
        precondition(flat.deletingLastPathComponent()==root)
        precondition(FileManager.default.fileExists(atPath:known.path))
        print("PASS disabled grouping stays flat; existing files untouched")
    }
}
