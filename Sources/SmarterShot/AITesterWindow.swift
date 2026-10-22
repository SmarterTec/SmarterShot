import AppKit
import UniformTypeIdentifiers

/// A review-only workspace. It reads a chosen image and copies suggestions on
/// request; it never renames, rewrites, or automatically analyzes captures.
@MainActor
final class AITesterWindow: NSWindowController, NSWindowDelegate, NSToolbarDelegate, NSTextFieldDelegate, NSTextViewDelegate {
    typealias Analyzer = @MainActor (URL) async throws -> ScreenshotAISuggestion
    private let analyzer: Analyzer
    private var analysisTask: Task<Void, Never>?
    private var generation = UUID()
    private(set) var selectedURL: URL?
    private(set) var isAnalyzing = false
    private let imageView = NSImageView()
    private let sourceLabel = NSTextField(labelWithString: "Choose a screenshot to begin")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let filename = NSTextField(string: "")
    private let descriptionView = NSTextView()
    private let progress = NSProgressIndicator()
    private let analyzeButton = NSButton(title: "Analyze", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let copyButton = NSButton(title: "Copy Suggestions", target: nil, action: nil)

    var suggestedFilename: String { filename.stringValue }
    var suggestedDescription: String { descriptionView.string }
    var statusMessage: String { status.stringValue }

    init(analyzer: @escaping Analyzer = ScreenshotAIService.describe) {
        self.analyzer = analyzer
        let window = NSWindow(contentRect: NSRect(x:0,y:0,width:1080,height:700),
                              styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        super.init(window:window)
        window.title = "On-Device AI Tester"
        window.subtitle = "SmarterShot"
        window.minSize = NSSize(width:850,height:640)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.toolbarStyle = .unified
        let toolbar = NSToolbar(identifier:"SmarterShot.AITester")
        toolbar.delegate = self; toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        let root = NSView(); window.contentView = root
        let preview = NSView()
        preview.wantsLayer = true
        preview.layer?.backgroundColor = NSColor.underPageBackgroundColor.cgColor
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.setAccessibilityLabel("Screenshot preview")
        imageView.imageAlignment = .alignCenter
        sourceLabel.font = .systemFont(ofSize:12)
        sourceLabel.textColor = .secondaryLabelColor
        sourceLabel.lineBreakMode = .byTruncatingMiddle
        for view in [imageView,sourceLabel] { preview.addSubview(view); view.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            sourceLabel.leadingAnchor.constraint(equalTo:preview.leadingAnchor,constant:20),
            sourceLabel.trailingAnchor.constraint(equalTo:preview.trailingAnchor,constant:-20),
            sourceLabel.bottomAnchor.constraint(equalTo:preview.bottomAnchor,constant:-16),
            imageView.leadingAnchor.constraint(equalTo:preview.leadingAnchor,constant:20),
            imageView.trailingAnchor.constraint(equalTo:preview.trailingAnchor,constant:-20),
            imageView.topAnchor.constraint(equalTo:preview.topAnchor,constant:20),
            imageView.bottomAnchor.constraint(equalTo:sourceLabel.topAnchor,constant:-16)
        ])
        let results = NSVisualEffectView()
        results.material = .sidebar; results.blendingMode = .withinWindow
        let fields = NSStackView(); fields.orientation = .vertical; fields.alignment = .leading; fields.spacing = 12
        results.addSubview(fields); fields.translatesAutoresizingMaskIntoConstraints = false
        func label(_ text:String,heading:Bool=false) -> NSTextField {
            let field = NSTextField(wrappingLabelWithString:text)
            field.font = .systemFont(ofSize:heading ? 14 : 12,weight:heading ? .semibold : .regular)
            return field
        }
        let title = label("Suggestions",heading:true)
        let privacy = label("Apple’s on-device AI • No files changed")
        privacy.textColor = .secondaryLabelColor
        filename.placeholderString = "Suggested filename"
        filename.setAccessibilityLabel("Suggested filename, editable")
        filename.font = .systemFont(ofSize:13); filename.delegate = self
        let descriptionScroll = NSScrollView()
        descriptionScroll.borderType = .bezelBorder; descriptionScroll.hasVerticalScroller = true
        descriptionView.frame = NSRect(x:0,y:0,width:300,height:150)
        descriptionView.minSize = NSSize(width:0,height:150)
        descriptionView.maxSize = NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
        descriptionView.isVerticallyResizable = true
        descriptionView.delegate = self
        descriptionView.isRichText = false
        descriptionView.isAutomaticQuoteSubstitutionEnabled = false
        descriptionView.font = .systemFont(ofSize:13)
        descriptionView.textContainerInset = NSSize(width:8,height:8)
        descriptionView.autoresizingMask = [.width]
        descriptionView.isHorizontallyResizable = false
        descriptionView.textContainer?.widthTracksTextView = true
        descriptionView.setAccessibilityLabel("Suggested description, editable")
        descriptionScroll.documentView = descriptionView
        descriptionScroll.heightAnchor.constraint(equalToConstant:150).isActive = true
        let help = label("Review or edit these suggestions. Copying them leaves your screenshot unchanged.")
        help.textColor = .secondaryLabelColor
        copyButton.target = self; copyButton.action = #selector(copySuggestions)
        copyButton.bezelStyle = .rounded
        status.font = .systemFont(ofSize:12); status.textColor = .secondaryLabelColor
        status.setAccessibilityLabel("Analysis status")
        progress.style = .spinning; progress.controlSize = .small; progress.isDisplayedWhenStopped = false
        let stateRow = NSStackView(views:[progress,status]); stateRow.alignment = .top; stateRow.spacing = 8
        for view in [title,privacy,label("Filename"),filename,label("Description"),descriptionScroll,help,copyButton,stateRow] {
            fields.addArrangedSubview(view)
        }
        for view in [privacy,filename,descriptionScroll,help,stateRow] {
            view.widthAnchor.constraint(equalTo:fields.widthAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            fields.leadingAnchor.constraint(equalTo:results.leadingAnchor,constant:20),
            fields.trailingAnchor.constraint(equalTo:results.trailingAnchor,constant:-20),
            fields.topAnchor.constraint(equalTo:results.topAnchor,constant:24),
            fields.bottomAnchor.constraint(lessThanOrEqualTo:results.bottomAnchor,constant:-20)
        ])
        for view in [preview,results] { root.addSubview(view); view.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            preview.leadingAnchor.constraint(equalTo:root.leadingAnchor),preview.topAnchor.constraint(equalTo:root.topAnchor),
            preview.bottomAnchor.constraint(equalTo:root.bottomAnchor),preview.trailingAnchor.constraint(equalTo:results.leadingAnchor),
            results.widthAnchor.constraint(equalToConstant:340),results.trailingAnchor.constraint(equalTo:root.trailingAnchor),
            results.topAnchor.constraint(equalTo:root.topAnchor),results.bottomAnchor.constraint(equalTo:root.bottomAnchor)
        ])
        analyzeButton.target = self; analyzeButton.action = #selector(analyzeAction)
        cancelButton.target = self; cancelButton.action = #selector(cancelAction)
        for button in [analyzeButton,cancelButton] { button.bezelStyle = .texturedRounded }
        resetStatus()
        updateControls()
        window.center()
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) not used") }

    func present(screenshot:URL? = nil) {
        if let screenshot = screenshot,screenshot != selectedURL { loadScreenshot(screenshot) }
        showWindow(nil); NSApp.activate(ignoringOtherApps:true); window?.makeKeyAndOrderFront(nil)
    }
    func toolbarDefaultItemIdentifiers(_ toolbar:NSToolbar)->[NSToolbarItem.Identifier] { [.init("choose"),.flexibleSpace,.init("cancel"),.init("analyze")] }
    func toolbarAllowedItemIdentifiers(_ toolbar:NSToolbar)->[NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbar(_ toolbar:NSToolbar,itemForItemIdentifier id:NSToolbarItem.Identifier,willBeInsertedIntoToolbar:Bool)->NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier:id)
        switch id.rawValue {
        case "choose":
            let button = NSButton(title:"Choose Screenshot…",target:self,action:#selector(chooseScreenshot))
            button.bezelStyle = .texturedRounded; item.view = button; item.label = "Choose Screenshot"
        case "cancel": item.view = cancelButton; item.label = "Cancel"
        case "analyze": item.view = analyzeButton; item.label = "Analyze"
        default: return nil
        }
        return item
    }
    @objc private func chooseScreenshot() {
        guard let window = window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png,.jpeg,.heic,.tiff,.bmp,.gif]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.prompt = "Choose Screenshot"
        panel.beginSheetModal(for:window) { [weak self] response in
            guard response == .OK,let url = panel.url else { return }
            self?.loadScreenshot(url)
        }
    }
    func loadScreenshot(_ url:URL) {
        cancelAnalysis()
        guard url.isFileURL,let image = NSImage(contentsOf:url) else {
            status.stringValue = "This file couldn’t be opened as an image."
            return
        }
        selectedURL = url; imageView.image = image
        sourceLabel.stringValue = url.lastPathComponent; sourceLabel.toolTip = url.path
        filename.stringValue = ""; descriptionView.string = ""
        analyzeButton.title = "Analyze"
        resetStatus(); updateControls()
    }
    private func resetStatus() { status.stringValue = ScreenshotAIService.availabilityMessage ?? "Choose Analyze to generate suggestions on this Mac." }
    private func updateControls() {
        analyzeButton.isEnabled = selectedURL != nil && !isAnalyzing
        cancelButton.isEnabled = isAnalyzing
        filename.isEditable = !isAnalyzing; descriptionView.isEditable = !isAnalyzing
        copyButton.isEnabled = !isAnalyzing && (!filename.stringValue.isEmpty || !descriptionView.string.isEmpty)
        if isAnalyzing { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
    }
    @objc private func analyzeAction() { analyze() }
    func analyze() {
        guard let url = selectedURL,!isAnalyzing else { return }
        generation = UUID(); let token = generation
        isAnalyzing = true; status.stringValue = "Analyzing on this Mac…"; updateControls()
        let analyzeImage = analyzer
        analysisTask = Task { [weak self] in
            do {
                let result = try await analyzeImage(url)
                guard !Task.isCancelled,let self = self,self.generation == token else { return }
                self.filename.stringValue = result.suggestedFilename(for:url,sourceAppName:CaptureSourceContext.read(from:url))
                self.descriptionView.string = result.description
                self.status.stringValue = "Ready for review. Your screenshot is unchanged."
                self.completeAnalysis()
            } catch {
                guard !Task.isCancelled,let self = self,self.generation == token else { return }
                self.status.stringValue = "Couldn’t generate suggestions. " + error.localizedDescription
                self.completeAnalysis()
            }
        }
    }
    private func completeAnalysis() {
        isAnalyzing = false; analysisTask = nil; analyzeButton.title = "Try Again"; updateControls()
    }
    @objc private func cancelAction() { cancelAnalysis(); status.stringValue = "Canceled. Your screenshot is unchanged." }
    func cancelAnalysis() {
        generation = UUID(); analysisTask?.cancel(); analysisTask = nil; isAnalyzing = false; updateControls()
    }
    @objc private func copySuggestions() {
        let text = filename.stringValue + "\n" + descriptionView.string
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text,forType:.string)
        status.stringValue = "Suggestions copied. Your screenshot is unchanged."
    }
    func controlTextDidChange(_ notification:Notification) { updateControls() }
    func textDidChange(_ notification:Notification) { updateControls() }
    func windowWillClose(_ notification:Notification) {
        if isAnalyzing { cancelAction() } else { cancelAnalysis() }
    }
}
