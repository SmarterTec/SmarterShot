import AppKit

/// A small always-on-top panel that shows step-by-step instructions and stays
/// visible (above other apps, e.g. System Settings) until the user closes it —
/// unlike a modal alert, which disappears as soon as you click a button.
final class InstructionsWindow: NSPanel {
    private static var current: InstructionsWindow?

    static func show(title: String, steps: [String]) {
        current?.close()
        let w = InstructionsWindow(headline: title, steps: steps)
        current = w
        w.orderFrontRegardless()
        // System Settings opens asynchronously; try a few times to dock beside it.
        for delay in [0.35, 0.8, 1.4] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak w] in
                w?.dockBesideSystemSettings()
            }
        }
    }

    /// Finds the System Settings window and moves this panel to the side of it
    /// that has room, so it isn't buried under notifications in the corner.
    func dockBesideSystemSettings() {
        guard let settings = Self.systemSettingsFrame() else { return }
        let screen = NSScreen.screens.first { $0.frame.intersects(settings) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        let margin: CGFloat = 16
        let w = frame.width, h = frame.height
        // Vertically align the panel's top with the Settings window's top.
        var y = settings.maxY - h
        y = min(max(y, visible.minY + margin), visible.maxY - h - margin)

        let rightX = settings.maxX + margin
        let leftX = settings.minX - margin - w
        let x: CGFloat
        if rightX + w <= visible.maxX {          // room on the right
            x = rightX
        } else if leftX >= visible.minX {        // room on the left
            x = leftX
        } else {                                 // overlap the right edge, below the notch/notifications
            x = visible.maxX - w - margin
            y = min(y, visible.maxY - h - 80)
        }
        setFrameOrigin(NSPoint(x: x, y: y))
        orderFrontRegardless()
    }

    /// System Settings window frame in AppKit (bottom-left origin) coordinates.
    private static func systemSettingsFrame() -> NSRect? {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                              kCGNullWindowID) as? [[String: Any]] ?? []
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        for info in list {
            guard let owner = info[kCGWindowOwnerName as String] as? String,
                  owner == "System Settings" || owner == "System Preferences",
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let b = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  b.width > 300 else { continue }
            let y = primaryHeight - b.origin.y - b.height // flip CG top-left → AppKit bottom-left
            return NSRect(x: b.origin.x, y: y, width: b.width, height: b.height)
        }
        return nil
    }

    private init(headline: String, steps: [String]) {
        let width: CGFloat = 330
        let pad: CGFloat = 18
        let contentWidth = width - pad * 2

        // Build step labels first so we can size the window to fit.
        var y: CGFloat = pad + 40 // leave room for the Done button
        var stepViews: [NSView] = []
        for (i, text) in steps.enumerated().reversed() {
            let l = NSTextField(wrappingLabelWithString: "\(i + 1).  \(text)")
            l.font = .systemFont(ofSize: 12)
            l.isSelectable = false
            l.preferredMaxLayoutWidth = contentWidth
            l.frame.size = NSSize(width: contentWidth, height: 0)
            l.sizeToFit()
            l.frame = NSRect(x: pad, y: y, width: contentWidth, height: l.frame.height)
            stepViews.append(l)
            y += l.frame.height + 10
        }

        let header = NSTextField(labelWithString: headline)
        header.font = .boldSystemFont(ofSize: 14)
        y += 4
        let headerY = y
        y += 24 + pad

        let height = y
        super.init(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                   styleMask: [.titled, .closable, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        title = "SmarterShot"
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false

        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        header.frame = NSRect(x: pad, y: headerY, width: contentWidth, height: 20)
        content.addSubview(header)
        stepViews.forEach { content.addSubview($0) }

        let done = NSButton(title: "Done", target: self, action: #selector(closePanel))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        done.frame = NSRect(x: width - pad - 88, y: pad - 4, width: 88, height: 30)
        content.addSubview(done)
        contentView = content

        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            setFrameOrigin(NSPoint(x: vf.maxX - width - 24, y: vf.maxY - height - 24))
        }
    }

    @objc private func closePanel() { close() }

    override func close() {
        InstructionsWindow.current = nil
        super.close()
    }
}
