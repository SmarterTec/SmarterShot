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
commits a filename edit. Existing files are never overwritten, and renaming is
blocked while that image is open in markup. Escape cancels a filename edit.
New screenshots record the source app from macOS, include it with the timestamp
in the saved name, and use that recorded app in AI filename suggestions. Window
capture uses the selected window's owner; area capture uses the window at the
selected region's center. Older/imported screenshots without this metadata can
still use the model's app identification.
Descriptions and suggested names are editable in the preview. Captures save and
appear immediately; automatic on-device analysis runs afterward, one image at a
time. Dismissing a preview cancels its analysis. Videos are not analyzed.

## On-device AI tester

Choose **Test On-Device AI…** from SmarterShot's menu-bar menu, select a screenshot,
and click **Analyze**. Suggested filenames preserve the capture timestamp, followed
by the app name when identifiable and a short subject (for example,
`2026-10-21 at 08.57.48 - Blender - rear-bumper.png`). For imported images without
a timestamp in the name, the file's creation date is used. Apple's local Vision
text recognition reads visible interface labels to help ground the on-device
model's filename and short preview description. Both results are editable; **Try Again** generates another
suggestion and **Copy Suggestions** copies your reviewed text.

The separate tester is manual and read-only: images are not renamed or modified
by its analysis or Copy action. Capture previews also analyze images in the
background; committing an inline filename edit renames that file. Generation uses only Apple's
`SystemLanguageModel` on this Mac, with no cloud provider, API key, or fallback.
Image analysis needs macOS 27 and Apple Intelligence enabled with its model ready.
The tester explains unavailability instead of switching services. Descriptions
may be inaccurate; review samples before using them for filenames or metadata.

For a local check: `./test-ai.sh` exercises read-only UI behavior, cancellation,
and image switching. To test the actual model with a chosen local image, use
`./test-ai.sh /absolute/path/to/screenshot.png`.

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
