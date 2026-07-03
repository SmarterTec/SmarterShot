import AppKit

// Menu-bar-only app. We build the NSApplication manually so we can run
// without a storyboard / Xcode project.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // no Dock icon, menu bar only
app.run()
