import AppKit
import SmarterShotCore

/// Facade over the two recording backends:
/// - macOS 15+: ScreenCaptureKit (`SCKRecorder`) — native pixels, 60 fps.
/// - older:    long-running `screencapture -v` stopped with SIGINT.
final class ScreenRecorder {
    static let shared = ScreenRecorder()

    private var legacyTask: Process?
    private var sckRecorder: Any? // SCKRecorder; typed Any so the class loads pre-macOS 15
    private var onFinish: ((CaptureController.Shot?) -> Void)?

    var isRecording: Bool { legacyTask != nil || sckRecorder != nil }

    func start(target: RecordingTarget, onFinish: @escaping (CaptureController.Shot?) -> Void) {
        guard !isRecording else { return }
        self.onFinish = onFinish
        let dest = CaptureController.uniqueDestination(ext: "mov")
        let captureAudio = ShortcutStore.recordAudio

        if #available(macOS 15.0, *) {
            let rec = SCKRecorder()
            sckRecorder = rec
            rec.start(target: target, dest: dest, captureAudio: captureAudio) { [weak self] fileURL in
                guard let self = self else { return }
                self.sckRecorder = nil
                self.deliver(fileURL)
            }
        } else {
            startLegacy(target: target, dest: dest, captureAudio: captureAudio)
        }
    }

    private func startLegacy(target: RecordingTarget, dest: URL, captureAudio: Bool) {
        // The legacy `screencapture -v` tool can only capture the microphone
        // (-g), not system audio, so system-audio recording is unavailable on
        // macOS 14 and earlier; record video only there.
        if captureAudio {
            CaptureController.log("REC legacy: system audio unsupported (macOS < 15), recording video only")
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        proc.arguments = ["-v"] + target.screencaptureArgs + [dest.path]
        CaptureController.log("REC START legacy \(proc.arguments!.joined(separator: " "))")

        proc.terminationHandler = { [weak self] p in
            CaptureController.log("REC END legacy status=\(p.terminationStatus)")
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.legacyTask = nil
                self.deliver(dest)
            }
        }

        do {
            try proc.run()
            legacyTask = proc
        } catch {
            CaptureController.log("REC FAILED to launch: \(error)")
            legacyTask = nil
            deliver(nil)
        }
    }

    /// Stops recording; the backend finalizes the file and the finish callback
    /// delivers it.
    func stop() {
        if #available(macOS 15.0, *), let rec = sckRecorder as? SCKRecorder {
            rec.stop()
            return
        }
        legacyTask?.interrupt()
    }

    private func deliver(_ url: URL?) {
        let cb = onFinish
        onFinish = nil
        guard let url = url, FileManager.default.fileExists(atPath: url.path) else {
            cb?(nil)
            return
        }
        let poster = CaptureController.posterFrame(url) ?? CaptureController.videoPlaceholder()
        cb?(CaptureController.Shot(url: url, image: poster, isVideo: true))
    }
}
