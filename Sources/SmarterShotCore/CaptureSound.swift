import Foundation

/// Names and flag logic for the capture sound the user picked in Settings.
/// Pure (no AppKit) so it lives in Core and can be unit-tested; the actual
/// playback lives in `SoundPlayer` in the app target.
public enum CaptureSound {
    /// Menu order for the Settings dropdown.
    public static let options = ["Bubble", "Blip", "Clack", "Shutter", systemDefault, none]
    public static let systemDefault = "System Default"
    public static let none = "None"
    public static let defaultName = systemDefault

    /// True when this option is one of our bundled WAVs (i.e. not a macOS one).
    public static func isCustom(_ name: String) -> Bool {
        name != systemDefault && name != none
    }

    /// Whether the `screencapture` tool's own shutter should be silenced (-x).
    /// We silence it whenever we're not deferring to the macOS default.
    public static func silenceSystemShutter(_ name: String) -> Bool {
        name != systemDefault
    }
}
