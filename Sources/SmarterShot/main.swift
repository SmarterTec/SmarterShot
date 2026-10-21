import AppKit

// Menu-bar-only app. We build the NSApplication manually so we can run
// without a storyboard / Xcode project.
let app = NSApplication.shared
// Also open an existing screenshot directly in the editor.
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--markup" {
    let url = URL(fileURLWithPath: CommandLine.arguments[2])
    if let image = NSImage(contentsOf: url) {
        app.setActivationPolicy(.accessory)
        _ = MarkupWindow(shot: CaptureController.Shot(url: url, image: image)) { edited in
            CaptureController.copyToClipboard(edited)
            _ = OverlayWindow(shot: edited)
        }
        app.run()
        exit(0)
    }
    fputs("Cannot open image for markup.\n", stderr)
    exit(1)
}
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // no Dock icon, menu bar only
app.run()
