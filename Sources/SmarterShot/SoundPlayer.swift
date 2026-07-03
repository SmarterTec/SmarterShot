import AppKit

/// Plays the capture sound the user picked in Settings. Custom sounds are
/// bundled WAVs in Resources/Sounds; two special options defer to macOS.
enum CaptureSound {
    /// Menu order for the Settings dropdown.
    static let options = ["Bubble", "Blip", "Clack", "Shutter", systemDefault, none]
    static let systemDefault = "System Default"
    static let none = "None"
    static let defaultName = systemDefault

    /// True when this option is one of our bundled WAVs (i.e. not a macOS one).
    static func isCustom(_ name: String) -> Bool {
        name != systemDefault && name != none
    }

    /// Whether the `screencapture` tool's own shutter should be silenced (-x).
    /// We silence it whenever we're not deferring to the macOS default.
    static func silenceSystemShutter(_ name: String) -> Bool {
        name != systemDefault
    }
}

enum SoundPlayer {
    private static var cache: [String: NSSound] = [:]

    private static func sound(named name: String) -> NSSound? {
        if let cached = cache[name] { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Sounds"),
              let sound = NSSound(contentsOf: url, byReference: true) else { return nil }
        cache[name] = sound
        return sound
    }

    /// The macOS screenshot ("Grab") sound, used to preview the System Default.
    private static let systemGrabPath =
        "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Grab.aif"

    /// Plays the given option on capture (no-op for System Default / None —
    /// screencapture itself plays the system sound in the default case).
    static func play(_ name: String) {
        guard CaptureSound.isCustom(name), let sound = sound(named: name) else { return }
        sound.stop() // restart if already playing
        sound.play()
    }

    /// Plays a preview for the Settings dropdown. Unlike `play`, this also
    /// previews the actual macOS sound for System Default.
    static func preview(_ name: String) {
        if name == CaptureSound.systemDefault {
            if let sound = cache[name] ?? NSSound(contentsOfFile: systemGrabPath, byReference: true) {
                cache[name] = sound
                sound.stop(); sound.play()
            }
            return
        }
        play(name)
    }
}
