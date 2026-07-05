import CoreGraphics
import Foundation
import SmarterShotCore

// A tiny, dependency-free test harness. XCTest ships only with full Xcode, and
// this repo is built with the Command Line Tools, so we roll our own: each
// `check` prints a line and a failure flips the process exit code to 1 so CI
// (and `./test.sh`) can gate on it.

var failures = 0
var passes = 0

func check(_ cond: Bool, _ msg: String, file: StaticString = #file, line: UInt = #line) {
    if cond { passes += 1; print("  ok  \(msg)") }
    else { failures += 1; print("  FAIL \(msg)  (\(file):\(line))") }
}

func checkEqual<T: Equatable>(_ actual: T, _ expected: T, _ msg: String,
                              file: StaticString = #file, line: UInt = #line) {
    check(actual == expected, "\(msg) — expected \(expected), got \(actual)", file: file, line: line)
}

func group(_ name: String, _ body: () -> Void) {
    print("\n▶ \(name)")
    body()
}

// MARK: - Window picking (the regression that made window recording silently no-op)

/// Build a CGWindowList-style info dict.
func win(number: Int, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat,
         layer: Int = 0, owner: String? = "Some App") -> [String: Any] {
    var d: [String: Any] = [
        kCGWindowNumber as String: number,
        kCGWindowLayer as String: layer,
        kCGWindowBounds as String: ["X": x, "Y": y, "Width": w, "Height": h] as [String: Any],
    ]
    if let owner = owner { d[kCGWindowOwnerName as String] = owner }
    return d
}

group("WindowPicker") {
    // Basic hit.
    checkEqual(WindowPicker.windowUnder(point: CGPoint(x: 100, y: 100),
                                        in: [win(number: 10, x: 0, y: 0, w: 200, h: 200)],
                                        ownWindowNumbers: [])?.id, CGWindowID(10),
               "picks the window under the point")

    // The core regression: owner name absent (redacted) must still pick.
    checkEqual(WindowPicker.windowUnder(point: CGPoint(x: 50, y: 50),
                                        in: [win(number: 11, x: 0, y: 0, w: 200, h: 200, owner: nil)],
                                        ownWindowNumbers: [])?.id, CGWindowID(11),
               "still picks when owner name is missing")

    // Skip our own full-screen overlay (by window number), pick the one beneath.
    checkEqual(WindowPicker.windowUnder(point: CGPoint(x: 10, y: 10),
                                        in: [win(number: 99, x: 0, y: 0, w: 3000, h: 2000),
                                             win(number: 12, x: 0, y: 0, w: 200, h: 200)],
                                        ownWindowNumbers: [99])?.id, CGWindowID(12),
               "skips our own overlay by window number")

    // Backstop: skip a SmarterShot-owned window by name too.
    checkEqual(WindowPicker.windowUnder(point: CGPoint(x: 10, y: 10),
                                        in: [win(number: 99, x: 0, y: 0, w: 3000, h: 2000, owner: "SmarterShot"),
                                             win(number: 13, x: 0, y: 0, w: 200, h: 200)],
                                        ownWindowNumbers: [])?.id, CGWindowID(13),
               "skips SmarterShot-owned window by name backstop")

    // Ignore non-zero layers (menu bar / overlay chrome).
    checkEqual(WindowPicker.windowUnder(point: CGPoint(x: 10, y: 10),
                                        in: [win(number: 20, x: 0, y: 0, w: 200, h: 200, layer: 25),
                                             win(number: 21, x: 0, y: 0, w: 200, h: 200, layer: 0)],
                                        ownWindowNumbers: [])?.id, CGWindowID(21),
               "ignores non-zero window layers")

    // Point outside everything → nil.
    check(WindowPicker.windowUnder(point: CGPoint(x: 500, y: 500),
                                   in: [win(number: 30, x: 0, y: 0, w: 100, h: 100)],
                                   ownWindowNumbers: []) == nil,
          "returns nil when the point misses every window")

    // Overlap → frontmost (first in list) wins.
    checkEqual(WindowPicker.windowUnder(point: CGPoint(x: 10, y: 10),
                                        in: [win(number: 40, x: 0, y: 0, w: 300, h: 300),
                                             win(number: 41, x: 0, y: 0, w: 300, h: 300)],
                                        ownWindowNumbers: [])?.id, CGWindowID(40),
               "picks the frontmost of overlapping windows")
}

// MARK: - Coordinate conversion (AppKit ↔ CoreGraphics global space)

group("ScreenGeometry") {
    let h: CGFloat = 1000

    let p = ScreenGeometry.cgPoint(fromAppKit: CGPoint(x: 200, y: 800), primaryHeight: h)
    checkEqual(p.x, 200, "point x is unchanged")
    checkEqual(p.y, 200, "point y flips about primary height")

    let p2 = ScreenGeometry.cgPoint(fromAppKit: CGPoint(x: 3274, y: 700), primaryHeight: h)
    checkEqual(p2.x, 3274, "point on a secondary display to the right maps straight through")
    checkEqual(p2.y, 300, "secondary-display y still flips correctly")

    let r = ScreenGeometry.cgRect(fromAppKit: CGRect(x: 10, y: 100, width: 40, height: 50), primaryHeight: h)
    checkEqual(r.minX, 10, "rect x unchanged")
    checkEqual(r.minY, 850, "rect top edge (maxY) becomes CG minY")
    checkEqual(r.width, 40, "rect width unchanged")
    checkEqual(r.height, 50, "rect height unchanged")

    let back = ScreenGeometry.cgPoint(fromAppKit: p, primaryHeight: h)
    checkEqual(back.y, 800, "the Y flip is its own inverse (round-trips)")
}

// MARK: - Recording target → screencapture args

group("RecordingTarget") {
    let area = RecordingTarget.area(CGRect(x: 3274.6, y: 195.2, width: 858.9, height: 563.4))
    checkEqual(area.screencaptureArgs, ["-R", "3274,195,858,563"],
               "area target formats -R with truncated integer coords")
    checkEqual(area.cgRect, CGRect(x: 3274.6, y: 195.2, width: 858.9, height: 563.4),
               "area target exposes its rect for the dim overlay")

    let win = RecordingTarget.window(21155, CGRect(x: 1696, y: 32, width: 2434, height: 1374))
    checkEqual(win.screencaptureArgs, ["-l", "21155"],
               "window target formats -l with the window id")
    checkEqual(win.cgRect, CGRect(x: 1696, y: 32, width: 2434, height: 1374),
               "window target exposes its picked bounds for the dim overlay")
}

// MARK: - Selection-overlay style invariants

group("SelectionOverlayStyle") {
    // THE window-record regression: the highlight "hole" over the hovered
    // window was drawn at alpha 0. macOS hit-tests transparent windows
    // per-pixel, so clicks on alpha-0 pixels fall through to the app beneath —
    // making the pick unclickable exactly where the user clicks. The hole must
    // stay comfortably above 0 (and below the dim, so it still reads as a hole).
    check(SelectionOverlayStyle.holeAlpha >= 0.05,
          "hole alpha must be >= 0.05 so clicks hit the overlay, not the app below")
    check(SelectionOverlayStyle.holeAlpha < SelectionOverlayStyle.dimAlpha,
          "hole must stay visually lighter than the surrounding dim")
    check(SelectionOverlayStyle.dimAlpha > 0 && SelectionOverlayStyle.dimAlpha < 1,
          "dim alpha stays translucent (0..1)")
    // The while-recording dim must stay lighter than the selection dim (the
    // desktop has to remain usable for the whole recording), and its hole is
    // drawn at alpha 0 by design — the legacy -R capture records those pixels,
    // so nothing may tint them.
    check(SelectionOverlayStyle.recordingDimAlpha > 0
            && SelectionOverlayStyle.recordingDimAlpha <= SelectionOverlayStyle.dimAlpha,
          "recording dim is lighter than (or equal to) the selection dim")
}

// MARK: - Capture-sound flag rules

group("CaptureSound") {
    check(CaptureSound.silenceSystemShutter("Bubble"), "silences screencapture shutter for a custom sound")
    check(CaptureSound.silenceSystemShutter("None"), "silences shutter for None")
    check(!CaptureSound.silenceSystemShutter(CaptureSound.systemDefault), "keeps shutter for System Default")
    check(CaptureSound.isCustom("Clack"), "Clack is a custom sound")
    check(!CaptureSound.isCustom(CaptureSound.systemDefault), "System Default is not custom")
    check(!CaptureSound.isCustom(CaptureSound.none), "None is not custom")
}

// MARK: - Summary

print("\n\(passes) passed, \(failures) failed.")
exit(failures == 0 ? 0 : 1)
