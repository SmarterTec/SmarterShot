import AppKit

/// The screenshot card reads this at click time, including for existing cards.
enum MarkupEditor: String, CaseIterable {
    case smarterShot, preview
    var title:String { self == .smarterShot ? "SmarterShot" : "Apple Preview" }
    static var preferred:MarkupEditor {
        get { UserDefaults.standard.string(forKey:"markupEditor").flatMap(MarkupEditor.init(rawValue:)) ?? .smarterShot }
        set { UserDefaults.standard.set(newValue.rawValue,forKey:"markupEditor") }
    }
    static var previewURL:URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier:"com.apple.Preview") }
}
