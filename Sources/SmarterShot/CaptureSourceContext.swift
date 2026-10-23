import AppKit
import Darwin

/// Application identity only: no window titles, document names or UI text.
/// nil means imported/no capture record; an empty value means the capture's
/// application could not be determined and must not be guessed by a model.
enum CaptureSourceContext {
    private static let attribute = "app.smartershot.sourceApplication"
    static func read(from url:URL) -> String? {
        let count = getxattr(url.path,attribute,nil,0,0,0)
        guard count >= 0,count <= 1024 else { return nil }
        var data = Data(count:count)
        let read = data.withUnsafeMutableBytes { getxattr(url.path,attribute,$0.baseAddress,count,0,0) }
        guard read == count else { return nil }
        return String(data:data,encoding:.utf8)
    }
    static func write(_ name:String?,to url:URL) {
        guard let name = name else { return }
        let data = Data(name.utf8)
        _ = data.withUnsafeBytes { setxattr(url.path,attribute,$0.baseAddress,data.count,0,0) }
    }
    static func applicationName(windowID:CGWindowID) -> String? {
        let windows = CGWindowListCopyWindowInfo(.optionIncludingWindow,windowID) as? [[String:Any]] ?? []
        guard let info = windows.first else { return nil }
        return applicationName(info:info)
    }
    static func applicationName(info:[String:Any]) -> String? {
        if let pid = info[kCGWindowOwnerPID as String] as? Int32,
           let app = NSRunningApplication(processIdentifier:pid),let name = app.localizedName { return name }
        return info[kCGWindowOwnerName as String] as? String
    }
    /// Finalize a new screenshot after its source app is known. Moving preserves
    /// image bytes and metadata. Folder failures leave the capture in its root
    /// folder; filename collisions always get a fresh numeric suffix.
    static func storeCapture(at source:URL,appName:String?,organizeByApp:Bool) -> URL {
        let app = safeComponent(appName ?? "")
        let root = source.deletingLastPathComponent()
        var folder = root
        if organizeByApp && !app.isEmpty {
            let grouped = root.appendingPathComponent(String(app.prefix(90)),isDirectory:true)
            do { try FileManager.default.createDirectory(at:grouped,withIntermediateDirectories:true); folder = grouped }
            catch { /* Preserve a successfully saved capture even if grouping fails. */ }
        }
        let stem = source.deletingPathExtension().lastPathComponent + (app.isEmpty ? "" : " - " + app)
        let ext = source.pathExtension.isEmpty ? "" : "." + source.pathExtension
        var destination = folder.appendingPathComponent(stem+ext)
        if destination == source { return source }
        var suffix = 2
        while FileManager.default.fileExists(atPath:destination.path) {
            destination = folder.appendingPathComponent(stem+" (\(suffix))"+ext); suffix += 1
        }
        do { try FileManager.default.moveItem(at:source,to:destination); return destination }
        catch { return source }
    }

    static func safeComponent(_ name:String) -> String {
        name.components(separatedBy:CharacterSet.alphanumerics.union(.whitespaces).inverted)
            .joined(separator:" ").split(whereSeparator: \.isWhitespace).joined(separator:" ")
    }
}
