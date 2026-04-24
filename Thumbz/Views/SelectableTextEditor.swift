import SwiftUI
import AppKit

/// SwiftUI text editor that wraps an NSTextView and exposes the selection range,
/// so toolbar actions (like "Color Selection") can mutate just the selected text.
struct SelectableTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        let tv = scroll.documentView as! NSTextView
        tv.delegate = context.coordinator
        tv.isEditable = true
        tv.isSelectable = true
        tv.isRichText = false
        tv.drawsBackground = true
        tv.backgroundColor = NSColor.black.withAlphaComponent(0.25)
        tv.font = .systemFont(ofSize: 13)
        tv.textColor = .white
        tv.insertionPointColor = .white
        tv.textContainerInset = NSSize(width: 6, height: 6)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.smartInsertDeleteEnabled = false
        tv.string = text
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? NSTextView else { return }
        if tv.string != text {
            let prevRange = tv.selectedRange()
            tv.string = text
            // Best-effort preserve selection.
            let clamped = NSRange(location: min(prevRange.location, text.utf16.count),
                                  length: min(prevRange.length, text.utf16.count - min(prevRange.location, text.utf16.count)))
            tv.setSelectedRange(clamped)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SelectableTextEditor
        init(_ parent: SelectableTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.selection = tv.selectedRange()
        }
    }
}
