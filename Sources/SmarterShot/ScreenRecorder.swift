import AppKit

/// Runs a long-running `screencapture -v …` recording that we start with an
/// explicit region (a screen rect via -R, or a window id via -l) and stop by
/// sending SIGINT, which makes screencapture finalize the .mov.
final class ScreenRecorder {
    static let shared = ScreenRecorder()

    private var task: Process?
    private var dest: URL?
    private var onFinish: ((CaptureController.Shot?) -> Void)?

    var isRecording: Bool { task != nil }

    /// - Parameter regionArgs: e.g. ["-R","x,y,w,h"] for an area, or ["-l","<id>"] for a window.
    func start(regionArgs: [String], onFinish: @escaping (CaptureController.Shot?) -> Void) {
        guard task == nil else { return }
        self.onFinish = onFinish
        let dest = CaptureController.uniqueDestination(ext: "mov")
        self.dest = dest

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        proc.arguments = ["-v"] + regionArgs + [dest.path]
        CaptureController.log("REC START \(proc.arguments!.joined(separator: " "))")

        proc.terminationHandler = { [weak self] p in
            CaptureController.log("REC END status=\(p.terminationStatus)")
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.task = nil
                let exists = FileManager.default.fileExists(atPath: dest.path)
                guard exists else { self.deliver(nil); return }
                let poster = CaptureController.posterFrame(dest) ?? CaptureController.videoPlaceholder()
                self.deliver(CaptureController.Shot(url: dest, image: poster, isVideo: true))
            }
        }

        do {
            try proc.run()
            task = proc
        } catch {
            CaptureController.log("REC FAILED to launch: \(error)")
            task = nil
            deliver(nil)
        }
    }

    /// Stops recording; screencapture finalizes the file on SIGINT.
    func stop() {
        task?.interrupt()
    }

    private func deliver(_ shot: CaptureController.Shot?) {
        let cb = onFinish
        onFinish = nil
        dest = nil
        cb?(shot)
    }
}
