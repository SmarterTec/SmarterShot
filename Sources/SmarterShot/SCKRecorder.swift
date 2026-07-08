import AVFoundation
import AppKit
import ScreenCaptureKit
import SmarterShotCore

/// Records with ScreenCaptureKit — the same engine as the system ⌘⇧5 recorder.
/// Native pixel resolution, 60 fps, and a proper encoder bitrate, which is a
/// big quality step up from the legacy `screencapture -v` output. macOS 15+
/// (needs SCRecordingOutput); older systems fall back to the legacy recorder.
@available(macOS 15.0, *)
final class SCKRecorder: NSObject, SCStreamDelegate, SCRecordingOutputDelegate {
    private var stream: SCStream?
    private var dest: URL?
    private var completion: ((URL?) -> Void)?
    private var captureAudio = false
    private var stopRequested = false
    private var finished = false

    /// Starts recording `target` into `dest`. When `captureAudio` is true the
    /// Mac's system audio is mixed into the file (our own process audio is
    /// always excluded). `completion` fires exactly once, on the main queue,
    /// with the finalized file URL (nil on failure/cancel).
    func start(target: RecordingTarget, dest: URL, captureAudio: Bool,
               completion: @escaping (URL?) -> Void) {
        self.dest = dest
        self.captureAudio = captureAudio
        self.completion = completion

        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { [weak self] content, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard let content = content else {
                    CaptureController.log("REC sck shareable-content failed: \(error?.localizedDescription ?? "?")")
                    self.finish(nil)
                    return
                }
                self.beginStream(target: target, content: content)
            }
        }
    }

    private func beginStream(target: RecordingTarget, content: SCShareableContent) {
        guard let dest = dest else { return }

        let config = SCStreamConfiguration()
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.showsCursor = true
        config.captureResolution = .best
        // System (app) audio. Always exclude our own process so the capture
        // sound / UI clicks never leak into the recording.
        config.capturesAudio = captureAudio
        config.excludesCurrentProcessAudio = true

        let filter: SCContentFilter
        let sizePoints: CGSize
        switch target {
        case .window(let id, _):
            guard let win = content.windows.first(where: { $0.windowID == id }) else {
                CaptureController.log("REC sck window \(id) not found")
                finish(nil)
                return
            }
            filter = SCContentFilter(desktopIndependentWindow: win)
            sizePoints = filter.contentRect.size
        case .area(let rect):
            guard let display = content.displays.first(where: { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) })
                    ?? content.displays.first else {
                CaptureController.log("REC sck no display for rect \(rect)")
                finish(nil)
                return
            }
            // Keep our own UI (recording dim, stop pill, preview panels) out of
            // the recording — excluding the application covers windows created
            // later too (the dim overlay appears after this snapshot is taken).
            let pid = ProcessInfo.processInfo.processIdentifier
            if let ownApp = content.applications.first(where: { $0.processID == pid }) {
                filter = SCContentFilter(display: display, excludingApplications: [ownApp], exceptingWindows: [])
            } else {
                filter = SCContentFilter(display: display, excludingWindows: [])
            }
            config.sourceRect = rect.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
            sizePoints = rect.size
        }

        // Record at native pixel scale (Retina-sharp).
        let scale = CGFloat(filter.pointPixelScale)
        config.width = max(2, Int((sizePoints.width * scale).rounded()))
        config.height = max(2, Int((sizePoints.height * scale).rounded()))

        let recConfig = SCRecordingOutputConfiguration()
        recConfig.outputURL = dest
        recConfig.outputFileType = .mov
        recConfig.videoCodecType = .h264

        let output = SCRecordingOutput(configuration: recConfig, delegate: self)
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        do {
            try stream.addRecordingOutput(output)
        } catch {
            CaptureController.log("REC sck addRecordingOutput failed: \(error)")
            finish(nil)
            return
        }
        self.stream = stream
        CaptureController.log("REC sck starting \(config.width)x\(config.height) "
            + "(@\(scale)x, 60fps h264, audio=\(captureAudio))")
        stream.startCapture { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    CaptureController.log("REC sck startCapture failed: \(error.localizedDescription)")
                    self.finish(nil)
                    return
                }
                // Stop was requested while we were still spinning up.
                if self.stopRequested { self.stop() }
            }
        }
    }

    func stop() {
        stopRequested = true
        guard let stream = stream else { return }
        stream.stopCapture { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    CaptureController.log("REC sck stopCapture: \(error.localizedDescription)")
                }
                // Finalization normally arrives via recordingOutputDidFinishRecording;
                // this is a safety net in case that callback never fires.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.finishIfNeeded() }
            }
        }
    }

    /// Deliver whatever file exists (used for both normal finish and the cases
    /// where the stream dies underneath us, e.g. the recorded window closed).
    private func finishIfNeeded() {
        guard !finished else { return }
        let url = dest.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
        finish(url)
    }

    private func finish(_ url: URL?) {
        guard !finished else { return }
        finished = true
        stream = nil
        let cb = completion
        completion = nil
        cb?(url)
    }

    // MARK: - SCRecordingOutputDelegate

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        DispatchQueue.main.async {
            CaptureController.log("REC sck finished")
            self.finishIfNeeded()
        }
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        DispatchQueue.main.async {
            CaptureController.log("REC sck failed: \(error.localizedDescription)")
            self.finishIfNeeded()
        }
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async {
            CaptureController.log("REC sck stream stopped: \(error.localizedDescription)")
            self.finishIfNeeded()
        }
    }
}
