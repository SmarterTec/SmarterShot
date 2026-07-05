import Foundation

/// Visual constants for the record-selection overlay. In Core (not the app
/// target) so the test harness can enforce the click-through invariant below.
public enum SelectionOverlayStyle {
    /// Dimming laid over the whole screen while selecting.
    public static let dimAlpha: Double = 0.30

    /// Alpha of the "hole" cut over the hovered/selected window.
    ///
    /// MUST stay comfortably above 0: the macOS window server hit-tests
    /// transparent windows per-pixel, and clicks on alpha-0 pixels fall through
    /// to the app underneath. The hole is exactly where the user clicks to pick
    /// a window for recording, so an alpha-0 hole makes window recording
    /// silently unclickable (that regression shipped once — see the test).
    /// 0.05 is visually indistinguishable from clear but reliably hit-testable.
    public static let holeAlpha: Double = 0.05

    /// Dim laid around the recorded region for the whole duration of a
    /// recording (the passive "spotlight"). Lighter than the selection dim so
    /// the rest of the desktop stays comfortably usable while recording.
    public static let recordingDimAlpha: Double = 0.18
}
