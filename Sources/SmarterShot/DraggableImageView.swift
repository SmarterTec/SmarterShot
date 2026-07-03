import AppKit

/// An image view you can drag out of the overlay directly into other apps
/// (Finder, Slack, Mail, etc.). It vends the underlying file URL.
final class DraggableImageView: NSImageView, NSDraggingSource {
    var fileURL: URL?
    /// Called when a drag starts, so the overlay can hide itself.
    var onDragWillBegin: (() -> Void)?
    /// Called when the drag ends; empty operation means it was cancelled.
    var onDragEnded: ((NSDragOperation) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isEditable = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return [.copy, .generic]
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        onDragWillBegin?()
    }

    func draggingSession(_ session: NSDraggingSession,
                         endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onDragEnded?(operation)
    }

    override func mouseDown(with event: NSEvent) {
        guard let fileURL = fileURL, let image = self.image else { return }

        let item = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
        let dragFrame = NSRect(origin: .zero, size: bounds.size)
        item.setDraggingFrame(dragFrame, contents: image)

        beginDraggingSession(with: [item], event: event, source: self)
    }
}
