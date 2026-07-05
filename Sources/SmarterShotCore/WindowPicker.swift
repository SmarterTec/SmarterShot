import CoreGraphics
import Foundation

/// Pure, testable geometry + window-selection helpers used by the capture
/// overlay. Kept free of AppKit/UI state so they can be unit-tested headlessly
/// (see the `SmarterShotTests` executable).
public enum ScreenGeometry {
    /// Convert an AppKit global point (origin bottom-left of the primary screen,
    /// Y up) to a CoreGraphics global point (origin top-left of the primary
    /// screen, Y down). Valid across all displays since both share the primary
    /// origin — only the Y axis flips.
    public static func cgPoint(fromAppKit p: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: p.x, y: primaryHeight - p.y)
    }

    /// Convert an AppKit global rect to a CoreGraphics global rect.
    public static func cgRect(fromAppKit r: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
}

public enum WindowPicker {
    /// Frontmost normal (layer-0) window under `point`, given the raw
    /// `CGWindowListCopyWindowInfo` dictionaries in front-to-back order.
    ///
    /// - `ownWindowNumbers`: window numbers belonging to our own app, always
    ///   skipped (the full-screen selection overlay, pinned windows, etc.).
    ///
    /// We deliberately do NOT require `kCGWindowOwnerName`: that field can be
    /// absent, and requiring it made the whole pick fail (returning nil) so
    /// window recording silently never started. Excluding by window number is
    /// both sufficient and reliable; the owner-name check is only a best-effort
    /// backstop when the name happens to be present.
    public static func windowUnder(point: CGPoint,
                                   in list: [[String: Any]],
                                   ownWindowNumbers: Set<Int>) -> (id: CGWindowID, cgRect: CGRect)? {
        for info in list { // front-to-back
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let idNum = info[kCGWindowNumber as String] as? Int,
                  let bDict = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bDict as CFDictionary),
                  rect.contains(point) else { continue }
            if ownWindowNumbers.contains(idNum) { continue }
            if let owner = info[kCGWindowOwnerName as String] as? String, owner == "SmarterShot" { continue }
            return (CGWindowID(idNum), rect)
        }
        return nil
    }
}
