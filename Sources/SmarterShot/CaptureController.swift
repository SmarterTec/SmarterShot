import AppKit
import AVFoundation
import SmarterShotCore

/// Runs the built-in macOS `screencapture` tool interactively so we get
/// Apple's native crosshair / window selection UI for free, then saves the
/// result into the user's chosen folder.
enum CaptureController {

    /// Where screenshots are saved (user-configurable in Settings). Falls back
    /// to ~/Pictures/Screenshots and always ensures the directory exists.
    static var saveFolder: URL {
        let url = ShortcutStore.saveFolder
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    struct Shot {
        let url: URL
        let image: NSImage
        var isVideo: Bool
        let sourceAppName: String?
        init(url:URL,image:NSImage,isVideo:Bool=false,sourceAppName:String?=nil) {
            self.url = url; self.image = image; self.isVideo = isVideo
            self.sourceAppName = sourceAppName ?? CaptureSourceContext.read(from:url)
        }
    }

    private static func timestampName(ext: String) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "SmarterShot \(df.string(from: Date())).\(ext)"
    }

    // MARK: - Screenshots

    /// Interactive area capture (crosshair).
    static func captureArea(completion: @escaping (Shot?) -> Void) {
        run(arguments: ["-i"], ext: "png", isVideo: false, completion: completion)
    }

    /// Interactive window capture — click a window to grab it.
    static func captureWindow(completion: @escaping (Shot?) -> Void) {
        // The selected window ID provides an authoritative owning application.
        // Reuse the existing window selector rather than guessing the frontmost
        // app after Apple's interactive capture tool has finished.
        SelectionOverlay.present(mode:.window) { target in
            guard case .window(let id,_) = target else { completion(nil); return }
            let name = CaptureSourceContext.applicationName(windowID:id) ?? ""
            run(arguments:["-l",String(id)],ext:"png",isVideo:false,sourceAppName:name,completion:completion)
        }
    }

    // Screen recording lives in ScreenRecorder (long-running + stoppable).

    /// Extra `screencapture` flags for the current sound choice: silence its
    /// built-in shutter (-x) unless the user chose the system default.
    private static var soundFlags: [String] {
        CaptureSound.silenceSystemShutter(ShortcutStore.soundName) ? ["-x"] : []
    }

    /// Returns a path in the save folder that does not already exist, adding a
    /// numeric suffix if two captures land in the same second.
    static func uniqueDestination(ext: String) -> URL {
        let base = timestampName(ext: ext)
        let name = (base as NSString).deletingPathExtension
        var candidate = saveFolder.appendingPathComponent(base)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = saveFolder.appendingPathComponent("\(name) (\(n)).\(ext)")
            n += 1
        }
        return candidate
    }

    private static func run(arguments: [String], ext: String, isVideo: Bool, sourceAppName:String? = nil,
                            completion: @escaping (Shot?) -> Void) {
        let dest = uniqueDestination(ext: ext)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // Sound flags only matter for screenshots; harmless for video.
        let args = soundFlags + arguments + [dest.path]
        task.arguments = args
        let errPipe = Pipe()
        task.standardError = errPipe

        log("START screencapture \(args.joined(separator: " "))")

        task.terminationHandler = { proc in
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let err = String(data: errData, encoding: .utf8) ?? ""
            let exists = FileManager.default.fileExists(atPath: dest.path)
            log("END status=\(proc.terminationStatus) fileExists=\(exists) stderr=\(err.trimmingCharacters(in: .whitespacesAndNewlines))")
            DispatchQueue.main.async {
                guard exists else {
                    completion(nil) // user cancelled — nothing written
                    return
                }
                var capturedApp = sourceAppName
                if !isVideo && capturedApp == nil {
                    if let region = CaptureSourceContext.capturedRegion(from:dest) {
                        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []
                        capturedApp = CaptureSourceContext.applicationAtCenter(of:region,in:windows,ownPID:ProcessInfo.processInfo.processIdentifier)
                    }
                    capturedApp = capturedApp ?? "" // A new capture must not fall back to an AI app guess.
                }
                var savedURL = dest
                let appComponent = CaptureSourceContext.safeComponent(capturedApp ?? "")
                if !appComponent.isEmpty {
                    let stem = dest.deletingPathExtension().lastPathComponent + " - " + appComponent
                    var candidate = dest.deletingLastPathComponent().appendingPathComponent(stem+"."+ext)
                    var suffix = 2
                    while FileManager.default.fileExists(atPath:candidate.path) {
                        candidate = dest.deletingLastPathComponent().appendingPathComponent(stem+" (\(suffix))."+ext); suffix += 1
                    }
                    do { try FileManager.default.moveItem(at:dest,to:candidate); savedURL = candidate }
                    catch { /* Keep the successful capture under its original name. */ }
                }
                CaptureSourceContext.write(capturedApp,to:savedURL)
                let image = isVideo ? (posterFrame(savedURL) ?? videoPlaceholder())
                                    : (NSImage(contentsOf:savedURL) ?? NSImage())
                if !isVideo { SoundPlayer.play(ShortcutStore.soundName) }
                completion(Shot(url:savedURL,image:image,isVideo:isVideo,sourceAppName:capturedApp))
            }
        }

        do {
            try task.run()
        } catch {
            log("FAILED to launch: \(error)")
            DispatchQueue.main.async { completion(nil) }
        }
    }

    /// Appends a diagnostic line to /tmp/smartershot.log.
    static func log(_ message: String) {
        let line = "\(Date()) \(message)\n"
        let url = URL(fileURLWithPath: "/tmp/smartershot.log")
        guard let data = line.data(using: .utf8) else { return }
        if let fh = try? FileHandle(forWritingTo: url) {
            fh.seekToEndOfFile(); fh.write(data); try? fh.close()
        } else {
            try? data.write(to: url)
        }
    }

    /// First-frame poster image for a recorded video (for the overlay thumbnail).
    static func posterFrame(_ url: URL) -> NSImage? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        guard let cg = try? gen.copyCGImage(at: time, actualTime: nil) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    static func videoPlaceholder() -> NSImage {
        NSImage(systemSymbolName: "film", accessibilityDescription: "Recording") ?? NSImage()
    }

    /// Permanently deletes the saved file.
    static func delete(_ shot: Shot) {
        try? FileManager.default.removeItem(at: shot.url)
    }

    /// Copy the capture to the clipboard so it can be pasted anywhere. For
    /// images we copy the picture itself (and deliberately NOT the file URL,
    /// which would leak the home path). For videos we copy the file reference.
    static func copyToClipboard(_ shot: Shot) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if shot.isVideo {
            pb.writeObjects([shot.url as NSURL])
        } else {
            pb.writeObjects([shot.image])
        }
    }
}
