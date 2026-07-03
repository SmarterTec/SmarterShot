import AppKit
import Carbon.HIToolbox

/// A global keyboard shortcut, stored as a Carbon key code + modifier mask so it
/// can be re-registered, plus a human-readable key label for display.
struct KeyboardShortcut: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var keyLabel: String

    /// e.g. "⌥⇧⌘4"
    var displayString: String {
        var s = ""
        if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonModifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if carbonModifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if carbonModifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        return s + keyLabel
    }

    /// True if at least one modifier is present (we reject bare keys so a
    /// shortcut can't hijack ordinary typing).
    var hasModifier: Bool {
        carbonModifiers & UInt32(cmdKey | optionKey | shiftKey | controlKey) != 0
    }

    static let defaultArea = KeyboardShortcut(
        keyCode: UInt32(kVK_ANSI_4),
        carbonModifiers: UInt32(cmdKey | shiftKey | optionKey),
        keyLabel: "4")

    static let defaultWindow = KeyboardShortcut(
        keyCode: UInt32(kVK_ANSI_5),
        carbonModifiers: UInt32(cmdKey | shiftKey | optionKey),
        keyLabel: "5")

    static let defaultRecordArea = KeyboardShortcut(
        keyCode: UInt32(kVK_ANSI_R),
        carbonModifiers: UInt32(cmdKey | shiftKey | optionKey),
        keyLabel: "R")

    static let defaultRecordWindow = KeyboardShortcut(
        keyCode: UInt32(kVK_ANSI_R),
        carbonModifiers: UInt32(cmdKey | controlKey | optionKey),
        keyLabel: "R")
}

/// Persists the user's shortcut choices (and the onboarding flag) in UserDefaults.
enum ShortcutStore {
    private static let defaults = UserDefaults.standard
    private static let areaKey = "areaShortcut"
    private static let windowKey = "windowShortcut"
    private static let recordAreaKey = "recordAreaShortcut"
    private static let recordWindowKey = "recordWindowShortcut"
    private static let onboardedKey = "hasCompletedOnboarding"
    private static let saveFolderKey = "saveFolderPath"

    /// Where screenshots are saved. Defaults to ~/Pictures/Screenshots.
    static var saveFolder: URL {
        get {
            if let path = defaults.string(forKey: saveFolderKey) {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
            return pictures.appendingPathComponent("Screenshots", isDirectory: true)
        }
        set { defaults.set(newValue.path, forKey: saveFolderKey) }
    }

    static var area: KeyboardShortcut {
        get { load(areaKey) ?? .defaultArea }
        set { save(newValue, areaKey) }
    }

    static var window: KeyboardShortcut {
        get { load(windowKey) ?? .defaultWindow }
        set { save(newValue, windowKey) }
    }

    static var recordArea: KeyboardShortcut {
        get { load(recordAreaKey) ?? .defaultRecordArea }
        set { save(newValue, recordAreaKey) }
    }

    static var recordWindow: KeyboardShortcut {
        get { load(recordWindowKey) ?? .defaultRecordWindow }
        set { save(newValue, recordWindowKey) }
    }

    static var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: onboardedKey) }
        set { defaults.set(newValue, forKey: onboardedKey) }
    }

    private static let soundKey = "captureSound"

    /// Name of the capture sound (see CaptureSound.options).
    static var soundName: String {
        get { defaults.string(forKey: soundKey) ?? CaptureSound.defaultName }
        set { defaults.set(newValue, forKey: soundKey) }
    }

    private static func load(_ key: String) -> KeyboardShortcut? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(KeyboardShortcut.self, from: data)
    }

    private static func save(_ shortcut: KeyboardShortcut, _ key: String) {
        if let data = try? JSONEncoder().encode(shortcut) {
            defaults.set(data, forKey: key)
        }
    }
}

/// Maps a recording NSEvent to a display label for the key (the part after the
/// modifiers). Falls back to the typed character, then a generic placeholder.
enum KeyLabelMap {
    static func label(for event: NSEvent) -> String {
        if let special = special[Int(event.keyCode)] { return special }
        if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
            let scalar = chars.unicodeScalars.first!
            // Ignore non-printing control characters.
            if scalar.value >= 0x20 && scalar.value != 0x7F {
                return chars.uppercased()
            }
        }
        return "Key\(event.keyCode)"
    }

    private static let special: [Int: String] = [
        kVK_Space: "Space",
        kVK_Return: "↩",
        kVK_Tab: "⇥",
        kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋",
        kVK_LeftArrow: "←",
        kVK_RightArrow: "→",
        kVK_UpArrow: "↑",
        kVK_DownArrow: "↓",
        kVK_Home: "↖",
        kVK_End: "↘",
        kVK_PageUp: "⇞",
        kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
}
