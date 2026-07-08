# Changelog

All notable changes to SmarterShot. This project follows
[Semantic Versioning](https://semver.org/).

## [Unreleased]
### Added
- The **Record system audio** setting is now also in the Settings window (under
  Capture sound), kept in sync with the menu-bar toggle.

## [1.3.0] - 2026-07-08
### Added
- **Record system audio** — screen recordings now capture the Mac's audio
  (app, video, game sound) by default. Toggle it from the menu bar with **Record
  System Audio**. SmarterShot's own sounds are always excluded, and your
  microphone is never recorded. (macOS 15+; the older recorder is video-only.)

## [1.2.0] - 2026-07-06
### Added
- **Recording spotlight** — while recording, the rest of the screen stays dimmed
  around a red-bordered cut-out over what's being captured. It follows the window
  if you move it, clicks pass straight through, and it never appears in the recording.
- **Esc stops a recording**, alongside the stop pill and pressing the hotkey again.
- **Test suite** — `./test.sh` runs headless unit checks (no Xcode required) for
  window picking, coordinate conversion, recording arguments, overlay invariants,
  and capture-sound rules.

### Changed
- **Much sharper recordings** — recording now uses ScreenCaptureKit (the same
  engine as ⌘⇧5): native pixel resolution, 60 fps H.264. macOS 14 and earlier
  keep the previous recorder.
- `make-app.sh` signs with the stable local identity by default, so macOS
  remembers the Screen Recording permission across rebuilds.

### Fixed
- **Window recording couldn't be started by clicking.** Clicks on the highlighted
  window fell through the fully transparent highlight cut-out (macOS hit-tests
  transparent windows per pixel) and background-app clicks were swallowed as
  activation clicks — so the pick never fired.
- **Dragging a fresh screenshot preview needed an extra click** before the drag
  would start; the first click now begins the drag immediately.
- Window picking no longer fails when macOS omits window owner names.

## [1.1.0] - 2026-07-03
### Added
- **Paste to dismiss** — after you paste a screenshot (⌘V or ⌃V), its preview
  clears itself a few seconds later. The saved file stays in your folder.

## [1.0.0] - 2026-07-03
The first release — a fast, local, menu-bar screenshot and recording tool for macOS.

### Added
- **Screenshots** of an area or a window, each with its own keyboard shortcut.
- **Screen recording** of an area or a window, with a floating stop button and timer.
- **Quick actions** — every capture pops into the corner to copy, reveal in Finder,
  pin, or drag straight into another app. The preview hides while you drag it out.
- **One-tap discard** — tap ✕ to reveal a trash button, or tap ✕ again to keep it.
- **Pin to screen** — keep a screenshot floating above all your windows.
- **Make it yours** — customize the shortcuts, the save folder, the capture sound
  (with previews), and launch at login.
- **Private by design** — everything stays on your Mac. No cloud, no account, no network.
