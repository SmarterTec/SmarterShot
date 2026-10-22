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
- **Markup** — native macOS toolbar and contextual inspector for curves,
  sketches, lines, arrows, boxes, ovals, text, and highlights. Choose colors,
  stroke widths, fonts, and text sizes. Text edits directly on the image.
- **Editable paths** — Edit Points stays enabled when reselecting an outline.
  Use Add Point and click an edge, or double-click an edge, on lines, arrows,
  boxes, ovals, curves, sketches, and highlights. Sketch handles stay hidden
  until editing is enabled. Arrowheads follow the final segment.
- **Crop adjustment** — drag the image behind the frame, zoom the image with
  the inspector slider, or resize the crop with its eight frame handles. Apply
  animates into the result; Cancel discards the draft. Export preserves source
  pixel resolution for the chosen region.
- **Save protection** — closing an edited screenshot or quitting the app offers
  Save a Copy, Replace Original, Discard Changes, and Keep Editing. Copies are
  separate PNGs beside the original; replacing preserves PNG/JPEG/TIFF formats.
  Includes undo/redo, pinch-to-zoom, and Copy. Video thumbnails do not offer markup.
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
Startup checks access without prompting. Optional auto-dismissal after pasting
uses Accessibility only if already granted; taking screenshots does not request
Accessibility permission.

### Hotkeys and the native shortcuts
SmarterShot uses `⇧⌘4` and `⇧⌘5`. macOS assigns those to its own screenshot
shortcuts by default, so to let SmarterShot own them you can disable the built-in
ones in **System Settings → Keyboard → Keyboard Shortcuts → Screenshots**
(uncheck "Save picture of selected area as a file" and "Screenshot and recording
options"). This is fully reversible.

### Code signing
`make-app.sh` requires the certificate fingerprint in `signing-identity.sha1`,
with its private key in the login keychain. The identity is named
**SmarterShot Local Signing 2026**. Builds fail if this identity is unavailable;
there is no ad-hoc fallback and no separate signing-keychain password.

Keep the certificate, app identifier, and designated requirement stable across
updates. Restoring a backup means importing the **same** identity, not generating
another certificate with the same name. A new identity requires a new screen
recording approval. Existing macOS privacy reminders can still occur independently.

The encrypted `.p12` recovery file includes the certificate and private key.
Its password is stored in the login keychain as **SmarterShot signing backup
password**, account **SmarterShot Local Signing 2026**. Keep a separate copy of
that password in your password manager for recovery after losing this Mac.
Never commit the `.p12`, recovery password, or private key. The fingerprint is
public and safe to commit.

For another signing setup, explicitly set `SMARTERSHOT_SIGN_ID` to an exact
40-character certificate fingerprint and optionally `SMARTERSHOT_SIGN_KC` to
its keychain. CI releases must provision the intended identity before building;
they will fail instead of shipping an ad-hoc-signed release when it is absent.
Run `./test-signing.sh` after a successful build to check that invalid signing
configuration fails without replacing the last signed bundle.

## Roadmap ideas
OCR (text from a selection via the Vision framework), a lightweight annotation
editor improvements, scrolling capture, and a settings UI for the hotkeys and save folder.

## License
MIT

## Markup checks

Run `./test-markup.sh` for the standalone AppKit checks covering curve bending,
additional points, undo/redo, drawing tools, export dimensions, and cropping.
An existing image can be opened with `SmarterShot --markup /path/to/image.png`.
