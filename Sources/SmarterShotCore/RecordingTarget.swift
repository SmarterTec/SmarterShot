import CoreGraphics

/// What to record: an explicit screen region or a specific window, both in
/// CoreGraphics global coordinates (origin at the primary display's top-left).
public enum RecordingTarget {
    case area(CGRect)
    case window(CGWindowID, CGRect)

    /// Region arguments for the legacy `screencapture -v` recorder.
    public var screencaptureArgs: [String] {
        switch self {
        case .area(let r):
            return ["-R", "\(Int(r.minX)),\(Int(r.minY)),\(Int(r.width)),\(Int(r.height))"]
        case .window(let id, _):
            return ["-l", "\(id)"]
        }
    }

    /// The recorded region in CG global coordinates (for `.window`, the
    /// window's bounds at pick time). Drives the recording dim overlay.
    public var cgRect: CGRect {
        switch self {
        case .area(let r): return r
        case .window(_, let r): return r
        }
    }
}
