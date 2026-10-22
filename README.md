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
- **Markup** — native macOS toolbar with a compact formatting popover for
  curves, sketches, lines, arrows, boxes, ovals, text, and highlights. Choose
  stroke and fill colors, widths, fonts, and text sizes. Text edits inline.
  Tools stay active after drawing; click an existing object to select it and
  its original tool.
- **Editable paths** — clicking an outline reveals its points. Double-click an
  edge to insert a point; hold an edge, then drag to bend it into a curve.
  Dense sketch strokes make room around held points for smooth reshaping.
  Closed shapes support optional fills. Shift-click points or Shift-drag a selection
  box to move several points together. Pause at the end of a sketch while
  keeping the pointer down to recognize a clean shape. Arrowheads follow the final segment.
- **Crop adjustment** — drag the image behind the frame, zoom the image with
  the mouse wheel, pinching or the crop slider, or resize the crop with its eight frame handles. Apply
  animates into the result; Cancel discards the draft. Export preserves source
  pixel resolution for the chosen region.
- **Save protection** — closing an edited screenshot or quitting the app offers
  Save a Copy, Replace Original, Discard Changes, and Keep Editing. Copies are
  separate PNGs beside the original; replacing preserves PNG/JPEG/TIFF formats.
  Includes undo/redo, mouse-wheel and pinch-to-zoom, and Copy.
  Trackpad scrolling pans; Option-scroll also zooms on precise scrolling devices. Video thumbnails do not offer markup.
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
- Xcode 27 Command Line Tools or newer (no full Xcode needed): `xcode-select --install`

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

Screenshot previews use native Liquid Glass on macOS 26 and later (a translucent
fallback on older versions) and stack at the bottom left. Removing one slides those above it
down. When the stack fills the screen, scroll over it to reach every preview;
there is no visible scrollbar or six-preview limit. Compact native glass controls
float over the thumbnail. A loading skeleton animates while on-device analysis
runs. Below the image, the description is an editable headline with one editable
AI filename underneath. Click into either field to edit; Return or clicking away
commits a filename edit. When analysis finishes, the AI filename automatically
renames the saved capture, retaining its timestamp and OS-recorded app name.
Name collisions receive a numeric suffix. Existing files are never overwritten, and renaming is
blocked while that image is open in markup. Escape cancels a filename edit.
New screenshots record the source app from macOS, include it with the timestamp
in the saved name, and use that recorded app in AI filename suggestions. Window
capture uses the selected window's owner; area capture uses the window at the
selected region's center. Older/imported screenshots without this metadata can
still use the model's app identification.
Descriptions and suggested names are editable in the preview. Captures save and
appear immediately; automatic on-device analysis runs afterward, one image at a
time. Dismissing a preview cancels its analysis. Videos are not analyzed.

In **Settings**, enable **Organize screenshots by app** to save new screenshots
in folders such as `Screenshots/Blender/`. It is off by default. Unknown apps go
in `Other`; recordings and existing files stay where they are. Inline filename
edits and markup copies stay in the same app folder.

## On-device screenshot descriptions

New captures automatically generate a preview description and rename the saved
file with the capture timestamp, OS-recorded app name, and a short subject, for
example `2026-10-21 at 08.57.48 - Blender - rear-bumper.png`. Both preview fields
are editable. Apple's local Vision text recognition reads visible interface
labels to help ground the on-device model's interpretation.

Generation uses only Apple's `SystemLanguageModel` on this Mac, with no cloud
provider, API key, or fallback. Image analysis needs macOS 27 and Apple
Intelligence enabled with its model ready. If unavailable, screenshots still save
with their capture timestamp and app name. Descriptions may be inaccurate.

For automated service checks, run `./test-ai.sh`; preview queue/cancellation and
filename behavior are covered by `./test-overlays.sh`.

## In-app updates

Use **Check for Updates…** from SmarterShot's menu-bar menu. The native updater
shows published GitHub releases, downloads a signed app, then offers installation
and restart. It checks daily by default; **Automatically Check for Updates**
toggles background checks. Installing always requires a choice from you.
Unpublished commits and prereleases are not installed.

Updates and their feed are signed with a separate Ed25519 key. The private key
stays in the login Keychain under Sparkle's **Private key for signing Sparkle
updates** item, account `app.smartershot.SmarterShot`. Only its public key is in
`update-public-key.txt`. Keep both this key and the app's original code-signing
identity for future releases; neither private key belongs in GitHub or CI.

To publish from this Mac after committing the finished source:

```sh
./release.sh 1.4.0                   # changelog commit and local tag
./package-update.sh 1.4.0            # signed app ZIP + signed appcast.xml
./test-updates.sh dist/update-v1.4.0 # signature, version, and tamper checks
git push origin HEAD v1.4.0          # reviewed source and tag
./publish-update.sh 1.4.0           # uploads assets and publishes release
```

Use a new version for every release. Build numbers come from full git history;
keep that history intact, and do not force-rewrite published release tags.
The tag workflow only prepares a draft: signing and publishing happen locally
so release keys never need to leave this Mac. The updater reads
`https://github.com/SmarterTec/SmarterShot/releases/latest/download/appcast.xml`.
The first updater-enabled release must be installed manually once.

## Roadmap ideas
OCR (text from a selection via the Vision framework), a lightweight annotation
editor improvements, scrolling capture, and a settings UI for the hotkeys and save folder.

## License
MIT

## Markup checks

Run `./test-markup.sh` for the standalone AppKit checks covering curve bending,
additional points, undo/redo, drawing tools, export dimensions, and cropping.
An existing image can be opened with `SmarterShot --markup /path/to/image.png`.

## Markup editor choice and sticky notes

In **Settings → Markup editor**, choose **SmarterShot** (the default) or **Apple
Preview**. The screenshot card's Markup button uses this choice immediately.
Preview opens the saved image in Apple's app; use its Markup toolbar and save
there. The screenshot card retires after a successful handoff, avoiding stale
copies of pixels edited externally. Pending AI naming stops before this handoff
so the path stays stable while Preview opens it.

SmarterShot's editor includes **Sticky Note**: click to place a yellow note and
edit inline. Return adds a line; click outside to finish. Double-click to edit
again, drag its background to move, or drag its upper-right handle to resize.
The Formatting popover controls its text font/size/color and background fill.
Notes support undo/redo and appear in saved/copied images. The editor window
uses native Liquid Glass on macOS 26+, with a system material fallback; image
pixels and exports stay unaffected by the window material.

## Full Page screenshots (no extensions)

Use **Capture Window**, then choose **Full Page** over the highlighted window,
or Shift-click it. A normal click still captures the visible window.
The glass Full Page button has a repeating accent shimmer (static with Reduce
Motion) to make it easier to discover. On macOS
15.2 or later, SmarterShot detects supported scrollable content using macOS
Accessibility. If access is missing, only choosing Full Page explains how to
enable it; regular screenshots and app startup do not request Accessibility.

Full Page visibly scrolls the largest supported vertical content area, captures
overlapping sections, and stitches them entirely on this Mac. No browser
extension, remote debugging, web-page reload, or cloud service is used. The result
contains the scrollable content rather than repeated window/browser chrome.
Progress and Cancel are available, and the original scrollbar position is
restored after success, cancellation, or failure. A failed restore is reported.
The saved image uses the same app folders and on-device AI preview/naming flow.

Apps must expose an adjustable vertical scrollbar through Accessibility. The
button is hidden for unsupported windows once access is enabled. Dynamic pages,
infinite feeds, protected content and ambiguous/repeated overlaps may not work;
SmarterShot reports failure rather than saving an incomplete full-page image.
Capture is limited to 100 sections, one minute, and 40 million output pixels.
Keep the selected window in place while capturing. Existing screen-capture
permission is used; Accessibility is an additional opt-in for this feature.

Run `./test-scroll.sh` for pixel-level stitching, sticky footers, size/section
limits, scroll restoration, failed capture and cancellation checks. `./test-selection.sh`
checks the native Full Page button, Shift-click, Escape, and the unchanged
recording picker.

For a user-initiated command-line capture, launch SmarterShot with
`--capture-window` while it is not already running; this opens the same picker.
