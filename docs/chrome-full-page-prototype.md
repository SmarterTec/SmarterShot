# Chrome Full Page prototype

Window Screenshot now offers **Full Page** for Google Chrome, using the current tab’s DevTools “Capture full size screenshot” command. **Scroll Capture** remains a separate explicit choice. Other apps keep scrolling capture. Recording is unchanged. Shift-click selects Full Page; Option-Shift-click selects scrolling.

No extension, debug port, new profile, page reload, cloud service or remote model is used. Chrome may open docked Developer Tools and also save a normal download. SmarterShot imports only a fresh PNG clipboard result after the verified capture command, keeps its usual timestamp/app metadata/folder/AI naming flow, and leaves Chrome’s download untouched. This relies on Chrome versions whose capture command also copies the screenshot; older versions may time out. It never silently switches to scrolling.

Prototype limits: English Chrome; docked DevTools; Accessibility must expose the DevTools document and command palette. Opening docked tools can narrow/reflow the page; it captures that rendered layout. Existing tools stay open. Tools opened by this operation are closed only when the same window/tab and a scoped close control can be verified. If focus changes, cleanup leaves them alone. No browser preference is changed. Lazy content that the site has not loaded may be absent. Image limit: 40 megapixels / 160 MB encoded PNG.

## Verification performed without desktop interaction

- App compiles with SDK 27.
- `test-chrome-capture.sh`: injected driver checks fresh-image polling, preparation failure, command failure, stale clipboard timeout, invalid image, cancellation and cleanup. No Chrome or windows are opened.
- `test-scroll.sh`: existing headless stitching/restore regression checks.
- Signed package identity verification before any installation.

## Manual acceptance after an approved install

1. In Chrome open a long, already-loaded page. Use SmarterShot Window Screenshot → Full Page. Confirm capture does not scroll; inspect the saved image’s beginning, end and width. Check whether tools close and whether Chrome also makes a download.
2. Start with docked tools already open. Capture again; tools should remain open. Compare page layout with tools closed/open.
3. Switch tabs/windows or cancel during capture. It must stop without sending commands to the new tab or importing an old clipboard image.
4. Try a non-English browser, an undocked tools window and an inaccessible page. An honest failure is expected; no scrolling should start automatically.
5. Use explicit Scroll Capture and a normal visible-window screenshot. Confirm both still work, with normal app folders, timestamp and automatic AI filename.

A read-only inspection after the first user test confirmed Chrome exposes the command field as `Quick open prompt`, with a separate suggestion field and a `>` command prefix. Matching now uses that field, preserves the prefix, accepts the category before or after the exact result title, and reuses an already-open command palette. Regression checks cover these labels and reject suggestion/Console/file-search fields. Timeout messages identify the failing stage rather than blaming language/docking.

The corrected command invocation, clipboard behavior and cleanup are **not yet desktop-tested**. No automated desktop test or installed-app restart is part of development validation.

## Primary references

- https://developer.chrome.com/docs/devtools/device-mode
- https://developer.chrome.com/docs/devtools/command-menu
- https://github.com/ChromeDevTools/devtools-frontend/blob/main/front_end/models/emulation/DeviceModeModel.ts
- https://github.com/ChromeDevTools/devtools-frontend/blob/main/front_end/core/platform/browser/HostRuntime.ts
