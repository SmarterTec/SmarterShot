import AppKit
import ServiceManagement
import SmarterShotCore

/// A single window used both for first-launch onboarding and for later editing
/// of the capture shortcuts and preferences. It only stores the user's choices
/// and asks the app to re-register hotkeys.
final class ConfigWindowController: NSObject, NSWindowDelegate {
    enum Mode { case onboarding, settings }

    private let mode: Mode
    private let onApply: () -> Void
    private var window: NSWindow!
    private var areaRecorder: ShortcutRecorderButton!
    private var windowRecorder: ShortcutRecorderButton!
    private var recordAreaRecorder: ShortcutRecorderButton!
    private var recordWindowRecorder: ShortcutRecorderButton!
    private var launchCheckbox: NSButton!
    private var savePathField: NSTextField!
    private var soundPopup: NSPopUpButton!
    private var recordAudioCheckbox: NSButton!
    private var finished = false

    init(mode: Mode, onApply: @escaping () -> Void) {
        self.mode = mode
        self.onApply = onApply
        super.init()
        buildWindow()
    }

    func show() {
        // A menu-bar (LSUIElement) app can still own a key window that receives
        // keyboard input — just activate and make the window key.
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.window.makeKey()
        }
    }

    // MARK: - Building

    private func buildWindow() {
        let width: CGFloat = 500, height: CGFloat = 574
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                          styleMask: [.titled, .closable],
                          backing: .buffered, defer: false)
        window.title = mode == .onboarding ? "Welcome to SmarterShot" : "SmarterShot Settings"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.level = .floating

        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        let pad: CGFloat = 24
        let fieldX = pad + 150
        let fieldW = width - pad - fieldX
        var y = height - 24 // top cursor, decremented as rows are added

        func addRow(_ text: String, _ shortcut: KeyboardShortcut) -> ShortcutRecorderButton {
            let l = label(text, size: 13, bold: false)
            l.frame = NSRect(x: pad, y: y - 24, width: 150, height: 22)
            content.addSubview(l)
            let r = ShortcutRecorderButton(shortcut: shortcut)
            r.frame = NSRect(x: fieldX, y: y - 26, width: fieldW, height: 28)
            content.addSubview(r)
            y -= 38
            return r
        }

        // Title.
        let title = label(mode == .onboarding ? "Welcome to SmarterShot 👋" : "SmarterShot Settings",
                          size: 20, bold: true)
        title.frame = NSRect(x: pad, y: y - 26, width: width - pad * 2, height: 28)
        content.addSubview(title)
        y -= 36

        // Subtitle.
        let subtitle = wrappingLabel(
            mode == .onboarding
                ? "Set your shortcuts, sound, and save location. You can change these anytime from the menu bar."
                : "Change your shortcuts, sound, and save location. Click a shortcut field and press the keys.",
            size: 12, secondary: true)
        subtitle.frame = NSRect(x: pad, y: y - 34, width: width - pad * 2, height: 34)
        content.addSubview(subtitle)
        y -= 48

        // Shortcut rows.
        areaRecorder = addRow("Capture area", ShortcutStore.area)
        windowRecorder = addRow("Capture window", ShortcutStore.window)
        recordAreaRecorder = addRow("Record area", ShortcutStore.recordArea)
        recordWindowRecorder = addRow("Record window", ShortcutStore.recordWindow)
        y -= 6

        // Save-to folder row.
        let saveLabel = label("Save to", size: 13, bold: false)
        saveLabel.frame = NSRect(x: pad, y: y - 22, width: 150, height: 22)
        content.addSubview(saveLabel)
        savePathField = NSTextField(labelWithString: ShortcutStore.saveFolder.path)
        savePathField.lineBreakMode = .byTruncatingMiddle
        savePathField.font = .systemFont(ofSize: 11)
        savePathField.textColor = .secondaryLabelColor
        savePathField.frame = NSRect(x: fieldX, y: y - 21, width: fieldW - 96, height: 20)
        content.addSubview(savePathField)
        let chooseButton = NSButton(title: "Choose…", target: self, action: #selector(chooseSaveFolder))
        chooseButton.bezelStyle = .rounded
        chooseButton.controlSize = .small
        chooseButton.frame = NSRect(x: width - pad - 86, y: y - 24, width: 86, height: 24)
        content.addSubview(chooseButton)
        y -= 40

        // Capture sound row.
        let soundLabel = label("Capture sound", size: 13, bold: false)
        soundLabel.frame = NSRect(x: pad, y: y - 24, width: 150, height: 22)
        content.addSubview(soundLabel)
        soundPopup = NSPopUpButton(frame: NSRect(x: fieldX, y: y - 26, width: 200, height: 26))
        soundPopup.addItems(withTitles: CaptureSound.options)
        soundPopup.selectItem(withTitle: ShortcutStore.soundName)
        soundPopup.target = self
        soundPopup.action = #selector(soundChanged)
        content.addSubview(soundPopup)
        y -= 40

        // Record system audio (on by default). Mirrors the menu-bar toggle.
        recordAudioCheckbox = NSButton(checkboxWithTitle: "Record system audio in screen recordings",
                                       target: self, action: #selector(toggleRecordAudio))
        recordAudioCheckbox.state = ShortcutStore.recordAudio ? .on : .off
        recordAudioCheckbox.toolTip = "Include the Mac's audio (app, video, game sound) in recordings"
        recordAudioCheckbox.frame = NSRect(x: pad, y: y - 22, width: width - pad * 2, height: 22)
        content.addSubview(recordAudioCheckbox)
        y -= 34

        // Conflict tip.
        let tip = wrappingLabel(
            "To use ⇧⌘4 or ⇧⌘5, turn off macOS's built-in screenshots first — or add ⌥ Option to any combo.",
            size: 11, secondary: true)
        tip.frame = NSRect(x: pad, y: y - 34, width: width - pad * 2, height: 34)
        content.addSubview(tip)
        y -= 44

        // Button to jump to the macOS keyboard-shortcuts settings.
        let disableButton = NSButton(title: "Turn Off macOS Screenshots…",
                                     target: self, action: #selector(openKeyboardShortcuts))
        disableButton.bezelStyle = .rounded
        disableButton.controlSize = .small
        disableButton.sizeToFit()
        disableButton.frame = NSRect(x: pad, y: y - 24, width: disableButton.frame.width + 20, height: 24)
        content.addSubview(disableButton)

        // Launch at login (bottom-left) + primary button (bottom-right).
        launchCheckbox = NSButton(checkboxWithTitle: "Launch SmarterShot at login",
                                  target: self, action: #selector(toggleLaunchAtLogin))
        launchCheckbox.frame = NSRect(x: pad, y: 30, width: width - pad * 2 - 140, height: 22)
        launchCheckbox.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        content.addSubview(launchCheckbox)

        let primary = NSButton(title: mode == .onboarding ? "Get Started" : "Done",
                               target: self, action: #selector(finishAction))
        primary.bezelStyle = .rounded
        primary.keyEquivalent = "\r"
        primary.frame = NSRect(x: width - pad - 120, y: 24, width: 120, height: 32)
        content.addSubview(primary)

        window.contentView = content
    }

    private func label(_ text: String, size: CGFloat, bold: Bool) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
        return l
    }

    private func wrappingLabel(_ text: String, size: CGFloat, secondary: Bool) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = .systemFont(ofSize: size)
        l.isSelectable = false
        if secondary { l.textColor = .secondaryLabelColor }
        return l
    }

    // MARK: - Actions

    /// Opens System Settings to Keyboard and shows a floating, stay-open
    /// instructions panel to guide the user the rest of the way.
    @objc private func openKeyboardShortcuts() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts",
        ]
        for string in candidates {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { break }
        }
        InstructionsWindow.show(
            title: "Free up ⇧⌘4 / ⇧⌘5",
            steps: [
                "In System Settings, click “Keyboard Shortcuts…”",
                "Select “Screenshots” on the left",
                "Uncheck the shortcut(s) you want to free up",
                "Click Done, then return to SmarterShot and record ⇧⌘4 or ⇧⌘5",
            ])
    }

    /// Persists the system-audio choice immediately (the menu-bar checkmark
    /// re-syncs from the stored value the next time the menu opens).
    @objc private func toggleRecordAudio() {
        ShortcutStore.recordAudio = (recordAudioCheckbox.state == .on)
    }

    /// Saves the chosen capture sound and plays a preview.
    @objc private func soundChanged() {
        let name = soundPopup.titleOfSelectedItem ?? CaptureSound.defaultName
        ShortcutStore.soundName = name
        SoundPlayer.preview(name)
    }

    /// Lets the user pick where screenshots are saved.
    @objc private func chooseSaveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose where SmarterShot saves screenshots and recordings"
        panel.directoryURL = ShortcutStore.saveFolder
        if panel.runModal() == .OK, let url = panel.url {
            ShortcutStore.saveFolder = url
            savePathField.stringValue = url.path
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if launchCheckbox.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSSound.beep()
        }
        launchCheckbox.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
    }

    @objc private func finishAction() {
        finish()
        window.close()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        ShortcutStore.area = areaRecorder.shortcut
        ShortcutStore.window = windowRecorder.shortcut
        ShortcutStore.recordArea = recordAreaRecorder.shortcut
        ShortcutStore.recordWindow = recordWindowRecorder.shortcut
        ShortcutStore.hasCompletedOnboarding = true
        onApply()
    }

    func windowWillClose(_ notification: Notification) {
        [areaRecorder, windowRecorder, recordAreaRecorder, recordWindowRecorder].forEach { $0?.cancelRecording() }
        finish() // apply even if closed via the red button
    }
}
