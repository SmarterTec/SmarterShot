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
    static func capturedRegion(from url:URL) -> CGRect? {
        let attribute = "com.apple.metadata:kMDItemScreenCaptureGlobalRect"
        let count = getxattr(url.path,attribute,nil,0,0,0)
        guard count > 0,count < 4096 else { return nil }
        var data = Data(count:count)
        let read = data.withUnsafeMutableBytes { getxattr(url.path,attribute,$0.baseAddress,count,0,0) }
        guard read == count,let values = (try? PropertyListSerialization.propertyList(from:data,format:nil)) as? [Double],values.count == 4 else { return nil }
        let rect = CGRect(x:values[0],y:values[1],width:values[2],height:values[3])
        return rect.width > 0 && rect.height > 0 ? rect : nil
    }
    static func applicationAtCenter(of rect:CGRect,in windows:[[String:Any]],ownPID:Int32) -> String? {
        let center = CGPoint(x:rect.midX,y:rect.midY)
        for info in windows {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? Int32) != ownPID,
                  let raw = info[kCGWindowBounds as String] as? [String:Any],
                  let bounds = CGRect(dictionaryRepresentation:raw as CFDictionary),bounds.contains(center) else { continue }
            return applicationName(info:info)
        }
        return nil
    }
    static func safeComponent(_ name:String) -> String {
        name.components(separatedBy:CharacterSet.alphanumerics.union(.whitespaces).inverted)
            .joined(separator:" ").split(whereSeparator: \.isWhitespace).joined(separator:" ")
    }
}
