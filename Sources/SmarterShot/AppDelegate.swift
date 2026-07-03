import AppKit
import CoreGraphics

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let githubURL = URL(string: "https://github.com/SmarterTec/SmarterShot")!

    private var statusItem: NSStatusItem!
    private var areaHotKey: HotKey?
    private var windowHotKey: HotKey?
    private var recordAreaHotKey: HotKey?
    private var recordWindowHotKey: HotKey?
    private var lastShot: CaptureController.Shot?
    private var configController: ConfigWindowController?

    private var areaMenuItem: NSMenuItem!
    private var windowMenuItem: NSMenuItem!
    private var recordAreaMenuItem: NSMenuItem!
    private var recordWindowMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register with the Screen Recording privacy system so SmarterShot appears
        // in the list and can be granted; shows the prompt if not yet determined.
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }

        setupStatusItem()
        rebind(warnOnFailure: false)

        if !ShortcutStore.hasCompletedOnboarding {
            showOnboarding()
        }
    }

    private var versionString: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        return "SmarterShot \(short)"
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = AppDelegate.makeMenuBarIcon()
        }

        let menu = NSMenu()

        let version = NSMenuItem(title: versionString, action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)
        menu.addItem(.separator())

        areaMenuItem = NSMenuItem(title: "Capture Area", action: #selector(captureArea), keyEquivalent: "")
        windowMenuItem = NSMenuItem(title: "Capture Window", action: #selector(captureWindow), keyEquivalent: "")
        recordAreaMenuItem = NSMenuItem(title: "Record Area", action: #selector(recordArea), keyEquivalent: "")
        recordWindowMenuItem = NSMenuItem(title: "Record Window", action: #selector(recordWindow), keyEquivalent: "")
        [areaMenuItem, windowMenuItem, recordAreaMenuItem, recordWindowMenuItem].forEach { menu.addItem($0) }
        menu.addItem(withTitle: "Pin Last Screenshot", action: #selector(pinLast), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Open Screenshots Folder", action: #selector(openFolder), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Help / View on GitHub", action: #selector(openGitHub), keyEquivalent: "")
        menu.addItem(withTitle: "Quit SmarterShot", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items where item.action != nil { item.target = self }
        statusItem.menu = menu
    }

    /// A monochrome template icon matching the app icon's glyph: a capture
    /// frame (four corner brackets) with a center crosshair.
    private static func makeMenuBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let lw: CGFloat = 1.7
            let arm: CGFloat = 4.6
            let inset: CGFloat = 2.2
            let minX = inset, minY = inset
            let maxX = size.width - inset, maxY = size.height - inset
            NSColor.black.setStroke()

            func bracket(_ a: NSPoint, _ corner: NSPoint, _ b: NSPoint) {
                let p = NSBezierPath()
                p.lineWidth = lw
                p.lineCapStyle = .round
                p.lineJoinStyle = .round
                p.move(to: a); p.line(to: corner); p.line(to: b)
                p.stroke()
            }
            bracket(NSPoint(x: minX, y: minY + arm), NSPoint(x: minX, y: minY), NSPoint(x: minX + arm, y: minY))
            bracket(NSPoint(x: maxX - arm, y: minY), NSPoint(x: maxX, y: minY), NSPoint(x: maxX, y: minY + arm))
            bracket(NSPoint(x: minX, y: maxY - arm), NSPoint(x: minX, y: maxY), NSPoint(x: minX + arm, y: maxY))
            bracket(NSPoint(x: maxX, y: maxY - arm), NSPoint(x: maxX, y: maxY), NSPoint(x: maxX - arm, y: maxY))

            let c = NSPoint(x: size.width / 2, y: size.height / 2)
            let h: CGFloat = 2.3
            let cross = NSBezierPath()
            cross.lineWidth = lw
            cross.lineCapStyle = .round
            cross.move(to: NSPoint(x: c.x - h, y: c.y)); cross.line(to: NSPoint(x: c.x + h, y: c.y))
            cross.move(to: NSPoint(x: c.x, y: c.y - h)); cross.line(to: NSPoint(x: c.x, y: c.y + h))
            cross.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    private func updateMenuTitles() {
        areaMenuItem.title = "Capture Area  (\(ShortcutStore.area.displayString))"
        windowMenuItem.title = "Capture Window  (\(ShortcutStore.window.displayString))"
        recordAreaMenuItem.title = "Record Area  (\(ShortcutStore.recordArea.displayString))"
        recordWindowMenuItem.title = "Record Window  (\(ShortcutStore.recordWindow.displayString))"
    }

    // MARK: - Hotkey binding

    private func rebind(warnOnFailure: Bool) {
        [areaHotKey, windowHotKey, recordAreaHotKey, recordWindowHotKey].forEach { $0?.invalidate() }

        let a = ShortcutStore.area, w = ShortcutStore.window
        let ra = ShortcutStore.recordArea, rw = ShortcutStore.recordWindow
        areaHotKey = HotKey(keyCode: a.keyCode, modifiers: a.carbonModifiers) { [weak self] in self?.captureArea() }
        windowHotKey = HotKey(keyCode: w.keyCode, modifiers: w.carbonModifiers) { [weak self] in self?.captureWindow() }
        recordAreaHotKey = HotKey(keyCode: ra.keyCode, modifiers: ra.carbonModifiers) { [weak self] in self?.recordArea() }
        recordWindowHotKey = HotKey(keyCode: rw.keyCode, modifiers: rw.carbonModifiers) { [weak self] in self?.recordWindow() }

        updateMenuTitles()

        if warnOnFailure {
            var failed: [String] = []
            if areaHotKey == nil { failed.append("Capture area (\(a.displayString))") }
            if windowHotKey == nil { failed.append("Capture window (\(w.displayString))") }
            if recordAreaHotKey == nil { failed.append("Record area (\(ra.displayString))") }
            if recordWindowHotKey == nil { failed.append("Record window (\(rw.displayString))") }
            if !failed.isEmpty { showConflictAlert(failed) }
        }
    }

    private func showConflictAlert(_ failed: [String]) {
        let alert = NSAlert()
        alert.messageText = "Couldn't register a shortcut"
        alert.informativeText = "These shortcuts appear to be in use by macOS or another app:\n\n"
            + failed.joined(separator: "\n")
            + "\n\nPick a different combination (adding ⌥ Option usually avoids conflicts), or "
            + "disable the built-in one in System Settings ▸ Keyboard ▸ Keyboard Shortcuts ▸ Screenshots."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Capture / record

    private func present(_ shot: CaptureController.Shot?) {
        guard let shot = shot else { return }
        self.lastShot = shot
        CaptureController.copyToClipboard(shot) // auto-copy for instant paste
        _ = OverlayWindow(shot: shot)
    }

    @objc private func captureArea() {
        CaptureController.captureArea { [weak self] shot in self?.present(shot) }
    }

    @objc private func captureWindow() {
        CaptureController.captureWindow { [weak self] shot in self?.present(shot) }
    }

    @objc private func recordArea() { beginRecording(mode: .area) }
    @objc private func recordWindow() { beginRecording(mode: .window) }

    private func beginRecording(mode: SelectionOverlay.Mode) {
        // If already recording, the hotkey/menu acts as a stop toggle.
        if ScreenRecorder.shared.isRecording {
            ScreenRecorder.shared.stop()
            return
        }
        SelectionOverlay.present(mode: mode) { [weak self] regionArgs in
            guard let self = self, let regionArgs = regionArgs else { return } // cancelled
            ScreenRecorder.shared.start(regionArgs: regionArgs) { [weak self] shot in
                RecordingIndicator.shared.hide()
                self?.present(shot)
            }
            RecordingIndicator.shared.show { ScreenRecorder.shared.stop() }
        }
    }

    @objc private func pinLast() {
        guard let shot = lastShot else { return }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let topLeft = NSPoint(x: screen.visibleFrame.minX + 60,
                              y: screen.visibleFrame.maxY - 60)
        _ = PinnedWindow(image: shot.image, at: topLeft)
    }

    @objc private func openFolder() {
        NSWorkspace.shared.open(CaptureController.saveFolder)
    }

    @objc private func openGitHub() {
        NSWorkspace.shared.open(AppDelegate.githubURL)
    }

    // MARK: - Onboarding / settings

    /// Unregister the global hotkeys so they don't fire while the user is
    /// recording a new one in the config window.
    private func suspendHotKeys() {
        [areaHotKey, windowHotKey, recordAreaHotKey, recordWindowHotKey].forEach { $0?.invalidate() }
        areaHotKey = nil; windowHotKey = nil; recordAreaHotKey = nil; recordWindowHotKey = nil
    }

    private func showOnboarding() {
        suspendHotKeys()
        configController = ConfigWindowController(mode: .onboarding) { [weak self] in
            self?.rebind(warnOnFailure: true)
        }
        configController?.show()
    }

    @objc private func showSettings() {
        suspendHotKeys()
        configController = ConfigWindowController(mode: .settings) { [weak self] in
            self?.rebind(warnOnFailure: true)
        }
        configController?.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
