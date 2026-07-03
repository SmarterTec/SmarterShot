import AppKit

/// A small floating "⏺ Stop" pill shown while recording, with an elapsed timer.
/// Clicking it (or pressing the record hotkey again) stops the recording.
final class RecordingIndicator {
    static let shared = RecordingIndicator()

    private var window: NSPanel?
    private var timeLabel: NSTextField?
    private var timer: Timer?
    private var seconds = 0
    private var onStop: (() -> Void)?

    func show(onStop: @escaping () -> Void) {
        hide()
        self.onStop = onStop
        seconds = 0

        let width: CGFloat = 132, height: CGFloat = 34
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let bg = NSVisualEffectView(frame: NSRect(origin: .zero, size: panel.frame.size))
        bg.material = .hudWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = height / 2
        bg.layer?.masksToBounds = true

        // Red recording dot.
        let dot = NSView(frame: NSRect(x: 14, y: height / 2 - 5, width: 10, height: 10))
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.layer?.cornerRadius = 5
        bg.addSubview(dot)

        // Elapsed time.
        let time = NSTextField(labelWithString: "0:00")
        time.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        time.textColor = .white
        time.frame = NSRect(x: 30, y: height / 2 - 9, width: 44, height: 18)
        bg.addSubview(time)
        timeLabel = time

        // Stop button.
        let stop = NSButton(title: "Stop", target: self, action: #selector(stopTapped))
        stop.bezelStyle = .rounded
        stop.controlSize = .small
        stop.frame = NSRect(x: width - 62, y: height / 2 - 12, width: 52, height: 24)
        bg.addSubview(stop)

        panel.contentView = bg

        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: vf.midX - width / 2, y: vf.maxY - height - 12))
        }
        panel.orderFrontRegardless()
        window = panel

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.seconds += 1
            self.timeLabel?.stringValue = String(format: "%d:%02d", self.seconds / 60, self.seconds % 60)
        }
    }

    func hide() {
        timer?.invalidate(); timer = nil
        window?.orderOut(nil); window = nil
        onStop = nil
    }

    @objc private func stopTapped() {
        onStop?()
    }
}
