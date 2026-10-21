# SmarterShot

A lightweight, native macOS menu-bar app for a faster screenshot workflow.
No cloud, no accounts, no telemetry — everything stays on your Mac.

Built with Swift + AppKit. The whole app is a ~200 KB bundle using ~40 MB RAM.

## Features
- **Screenshots** — capture an **area** or a **window** using macOS's native
  selection UI, each on its own global hotkey.
- **Screen recording** — record an **area** or **window** to `.mov`, each on its
  own hotkey.
- **Corner overlay** — after each capture a thumbnail pops into the bottom-left
  with **Copy**, **Reveal**, **Pin**, and **Markup**. It stays until you dismiss it, and
  multiple captures **stack** upward. The overlay hides while you drag the image out.
- **Markup** — draw smooth editable curves, freehand strokes, lines, arrows,
  boxes, ovals, text, and translucent highlights. Choose colors and widths,
  move shapes with Select, and use Edit Points to reveal handles.
  Double-click curves, boxes, or ovals to add outline points. Sketch handles stay
  hidden until Edit Points is enabled. Text edits directly on the image and
  returns to Select automatically, with font, size, color, and a resize handle. Includes centered image fitting, an animated crop view, undo/redo, pinch-to-zoom, Copy, and
  Save Copy. Saves a separate PNG beside the original at the original pixel
  resolution (or selected crop size). Video thumbnails do not offer markup.
- **Inline discard** — tap the ✕ to reveal a red trash; tap ✕ again to keep, or
  the trash to delete the file.
- **Customizable in Settings** — set each shortcut, the save folder, the capture
  sound, and launch-at-login.
- **Capture sounds** — choose Bubble / Blip / Clack / Shutter / the macOS default
  / None, with in-app previews.
- **Auto-copy** to the clipboard, **drag-out** to any app, **pin-to-screen**
  floating windows, and **system light/dark** appearance.
- Saves to `~/Pictures/Screenshots` by default. Local only — no cloud, no network.

## Requirements
- macOS 13 or later
- Xcode Command Line Tools (no full Xcode needed): `xcode-select --install`

## Build & install
```sh
./make-app.sh                    # compiles, assembles, and signs dist/SmarterShot.app
cp -R dist/SmarterShot.app /Applications/
open /Applications/SmarterShot.app
```

### First run
macOS will ask for **Screen Recording** permission the first time you capture:
**System Settings → Privacy & Security → Screen Recording → enable SmarterShot**,
then trigger the capture again. This is a macOS requirement for any screenshot tool.

### Hotkeys and the native shortcuts
SmarterShot uses `⇧⌘4` and `⇧⌘5`. macOS assigns those to its own screenshot
shortcuts by default, so to let SmarterShot own them you can disable the built-in
ones in **System Settings → Keyboard → Keyboard Shortcuts → Screenshots**
(uncheck "Save picture of selected area as a file" and "Screenshot and recording
options"). This is fully reversible.

### Code signing note
By default `make-app.sh` ad-hoc signs the app, which is fine for local personal
use. Ad-hoc signatures change every build, so macOS re-asks for Screen Recording
permission after each rebuild. If that bothers you, sign with a stable local
self-signed identity by setting `SMARTERSHOT_SIGN_ID` / `SMARTERSHOT_SIGN_KC` /
`SMARTERSHOT_SIGN_PW` env vars (see the comments in `make-app.sh`). No credentials
are stored in this repo.

## Roadmap ideas
OCR (text from a selection via the Vision framework), a lightweight annotation
editor improvements, scrolling capture, and a settings UI for the hotkeys and save folder.

## License
MIT

## Markup checks

Run `./test-markup.sh` for the standalone AppKit checks covering curve bending,
additional points, undo/redo, drawing tools, export dimensions, and cropping.
An existing image can be opened with `SmarterShot --markup /path/to/image.png`.
