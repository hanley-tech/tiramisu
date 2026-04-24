import SwiftUI
import AppKit

struct DebugConsoleView: View {
    private let console = Log.console
    @State private var filter: String = ""
    @State private var autoscroll: Bool = true
    @State private var level: String = "all"

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            LogTextView(
                entries: filtered,
                autoscroll: autoscroll
            )
        }
        .frame(minWidth: 640, minHeight: 360)
    }

    private var filtered: [Entry] {
        console.entries.filter { e in
            (level == "all" || e.level == level) &&
            (filter.isEmpty || e.message.localizedCaseInsensitiveContains(filter) ||
             e.level.localizedCaseInsensitiveContains(filter))
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            TextField("Filter", text: $filter)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
            Picker("", selection: $level) {
                Text("all").tag("all")
                Text("info").tag("info")
                Text("warn").tag("warn")
                Text("error").tag("error")
            }
            .labelsHidden()
            .frame(width: 90)
            Toggle("Auto-scroll", isOn: $autoscroll).toggleStyle(.checkbox)
            Spacer()
            Text("\(filtered.count) / \(console.entries.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Button("Copy All") { copyAll() }
            Button("Reveal Log") { Log.shared.reveal() }
            Button("Clear") { Log.console.clear() }
        }
        .padding(8)
    }

    private func copyAll() {
        let text = filtered.map { formatEntry($0) }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    private func formatEntry(_ e: Entry) -> String {
        "\(timestamp(e.date)) [\(e.level)] \(e.message)"
    }
    private func timestamp(_ d: Date) -> String {
        let df = DateFormatter(); df.dateFormat = "HH:mm:ss.SS"
        return df.string(from: d)
    }
}

/// NSTextView-backed log display so the user can select across lines and copy.
private struct LogTextView: NSViewRepresentable {
    let entries: [Entry]
    let autoscroll: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor.black.withAlphaComponent(0.85)

        let tv = scroll.documentView as! NSTextView
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = true
        tv.backgroundColor = .clear
        tv.textContainerInset = NSSize(width: 10, height: 6)
        tv.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isRichText = true
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? NSTextView, let ts = tv.textStorage else { return }
        let attr = buildAttributed()
        ts.setAttributedString(attr)
        if autoscroll {
            tv.scrollRangeToVisible(NSRange(location: ts.length, length: 0))
        }
    }

    private func buildAttributed() -> NSAttributedString {
        let out = NSMutableAttributedString()
        let df = DateFormatter(); df.dateFormat = "HH:mm:ss.SS"
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular),
            .foregroundColor: NSColor.white,
        ]
        let muted: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        for e in entries {
            let ts = df.string(from: e.date)
            out.append(NSAttributedString(string: ts + "  ", attributes: muted))
            let color: NSColor
            switch e.level {
            case "warn": color = .systemYellow
            case "error": color = .systemRed
            case "debug": color = .systemTeal
            default: color = .systemGreen
            }
            let lv: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .semibold),
                .foregroundColor: color,
            ]
            out.append(NSAttributedString(string: e.level.uppercased().padding(toLength: 6, withPad: " ", startingAt: 0), attributes: lv))
            out.append(NSAttributedString(string: e.message + "\n", attributes: base))
        }
        return out
    }
}
