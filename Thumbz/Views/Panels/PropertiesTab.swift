import SwiftUI
import RichTextKit
import AppKit

struct PropertiesTab: View {
    @Environment(DocumentStore.self) private var store
    @State private var displayedID: UUID?

    private var displayedLayer: PXLayer? {
        store.layers.first(where: { $0.id == displayedID })
    }

    var body: some View {
        let _ = perfMark("PropertiesTab.body")
        Group {
        if let layer = displayedLayer {
            VStack(spacing: 0) {
                SectionDisclosure(title: "LAYER", defaultOpen: true) {
                    LayerBasics(layer: layer)
                }
                if layer.kind == .text {
                    SectionDisclosure(title: "TEXT", defaultOpen: true) {
                        TextEditorPanel(layer: layer)
                    }
                }
                if layer.kind == .gradient {
                    SectionDisclosure(title: "GRADIENT", defaultOpen: true) {
                        GradientEditorPanel(layer: layer)
                    }
                }
                if layer.kind == .solid {
                    SectionDisclosure(title: "SOLID COLOR", defaultOpen: true) {
                        SolidEditorPanel(layer: layer)
                    }
                }
                if layer.smart != nil {
                    SectionDisclosure(title: "SMART OBJECT", defaultOpen: true) {
                        SmartObjectPanel(layer: layer)
                    }
                    SectionDisclosure(title: "CUTOUT / BACKGROUND", defaultOpen: true) {
                        CutoutPanel(layer: layer)
                    }
                }
            }
        } else {
            Text("Select a layer.")
                .foregroundStyle(.secondary)
                .padding()
        }
        }
        .task(id: store.activeLayerID) {
            await Task.yield()
            displayedID = store.activeLayerID
        }
    }
}

private struct LayerBasics: View {
    @Environment(DocumentStore.self) private var store
    @Bindable var layer: PXLayer
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Name") {
                TextField("", text: $layer.name).textFieldStyle(.roundedBorder)
            }
            LabeledContent("Opacity") {
                HStack {
                    Slider(value: $layer.opacity, in: 0...1).onChange(of: layer.opacity) { store.invalidate() }
                    Text("\(Int(layer.opacity * 100))").font(.caption.monospacedDigit()).frame(width: 32, alignment: .trailing)
                }
            }
            LabeledContent("Blend") {
                Picker("", selection: $layer.blend) {
                    ForEach(BlendMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .onChange(of: layer.blend) { store.invalidate() }
            }
        }
    }
}

/// Box to hold a weak reference to the rich text view for post-action sync.
@MainActor
private final class RichTextViewComponentProxy {
    weak var view: (any RichTextViewComponent)?
}

private struct TextEditorPanel: View {
    @Environment(DocumentStore.self) private var store
    @Bindable var layer: PXLayer
    @State private var attributedText: NSAttributedString = .init(string: "")
    @StateObject private var richContext = RichTextContext()
    @State private var hasLoaded: Bool = false
    @State private var loadedLayerID: UUID?
    @State private var textViewProxy: RichTextViewComponentProxy = .init()
    @State private var inlineColor: Color = .red
    @State private var savedSelection: NSRange = .init(location: 0, length: 0)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RichTextEditor(text: $attributedText, context: richContext) { view in
                // Capture the underlying NSTextView so we can re-read its
                // attributed string after toolbar actions (which RichTextKit
                // doesn't auto-sync back to the text binding).
                textViewProxy.view = view
            }
                .frame(height: 90)
                .background(Color.black.opacity(0.25))
                .cornerRadius(4)
                .onAppear { loadFromLayer() }
                .onChange(of: layer.id) { _, _ in loadFromLayer() }
                .onChange(of: attributedText) { _, _ in
                    saveToLayer()
                    // Also capture latest selection so color can be applied after focus change.
                    if let view = textViewProxy.view as? NSTextView {
                        let r = view.selectedRange()
                        if r.length > 0 { savedSelection = r }
                    }
                }
                .onReceive(richContext.actionPublisher) { action in
                    tlog("text action: \(action)")
                    // Stash the selection at action time so the color picker can
                    // apply to what the user had selected, even if focus changed.
                    if let view = textViewProxy.view {
                        let r = (view as? NSTextView)?.selectedRange() ?? NSRange(location: 0, length: 0)
                        if r.length > 0 { savedSelection = r }
                    }
                    // Toolbar actions (setColor / setStyle / toggleStyle) mutate
                    // the NSTextView directly without firing `textDidChange`.
                    // Pull the updated attributed string on the next tick and
                    // feed it back through the binding so saveToLayer runs.
                    DispatchQueue.main.async {
                        guard let view = textViewProxy.view else {
                            tlog("text sync: no textView proxy")
                            return
                        }
                        let latest = view.attributedString
                        tlog("text sync: editor has \(latest.length) chars, binding has \(attributedText.length)")
                        if !latest.isEqual(to: attributedText) {
                            attributedText = latest
                            tlog("text sync: pushed latest into binding")
                        }
                    }
                }

            HStack(spacing: 6) {
                // Our own color picker — applies directly to the NSTextView's
                // textStorage so we don't depend on RichTextKit's action round-trip
                // (which silently drops colors when the color panel steals focus).
                ColorPicker("", selection: $inlineColor)
                    .labelsHidden()
                    .frame(width: 28)
                    .help("Color for the selected text")
                    .onChange(of: inlineColor) { _, newColor in
                        applyInlineColor(NSColor(newColor))
                    }
                Button {
                    richContext.actionPublisher.send(.toggleStyle(.bold))
                } label: { Image(systemName: "bold") }
                .buttonStyle(.bordered).controlSize(.small)
                Button {
                    richContext.actionPublisher.send(.toggleStyle(.italic))
                } label: { Image(systemName: "italic") }
                .buttonStyle(.bordered).controlSize(.small)
                Button {
                    richContext.actionPublisher.send(.toggleStyle(.underlined))
                } label: { Image(systemName: "underline") }
                .buttonStyle(.bordered).controlSize(.small)
                Button {
                    richContext.actionPublisher.send(.toggleStyle(.strikethrough))
                } label: { Image(systemName: "strikethrough") }
                .buttonStyle(.bordered).controlSize(.small)
                Spacer()
            }
            Text("Select any part of the text, then pick a color / bold / italic / underline / strike to style just that range.")
                .font(.caption).foregroundStyle(.secondary)

            Divider().padding(.vertical, 2)

            LabeledContent("Font") {
                Picker("", selection: $layer.text.fontName) {
                    Section("System (SF Pro)") {
                        ForEach(TextFontResolver.systemFamilies, id: \.self) { Text($0).tag($0) }
                    }
                    Section("Installed") {
                        ForEach(TextFontResolver.installedFamilies, id: \.self) { Text($0).tag($0) }
                    }
                }
                .labelsHidden()
                .onChange(of: layer.text.fontName) { store.invalidate() }
            }
            LabeledContent("Weight (default)") {
                Picker("", selection: $layer.text.weight) {
                    ForEach(TextFontResolver.weights, id: \.value) { w in
                        Text(w.label).tag(w.value)
                    }
                }
                .labelsHidden()
                .onChange(of: layer.text.weight) { store.invalidate() }
            }
            LabeledContent("Size") {
                HStack {
                    Slider(value: $layer.text.fontSize, in: 8...600)
                        .onChange(of: layer.text.fontSize) { store.invalidate() }
                    Text("\(Int(layer.text.fontSize))").font(.caption.monospacedDigit()).frame(width: 40, alignment: .trailing)
                }
            }
            LabeledContent("Default Color") {
                ColorPicker("", selection: Binding(
                    get: { layer.text.color.swiftUIColor },
                    set: { layer.text.color = ColorRGB($0.asNSColor); store.invalidate() }
                )).labelsHidden()
            }
            LabeledContent("Align") {
                Picker("", selection: $layer.text.alignment) {
                    Text("Left").tag("left"); Text("Center").tag("center"); Text("Right").tag("right")
                }
                .pickerStyle(.segmented).labelsHidden()
                .onChange(of: layer.text.alignment) { store.invalidate() }
            }
            LabeledContent("Line Height") {
                Slider(value: $layer.text.lineHeight, in: 0.7...1.8)
                    .onChange(of: layer.text.lineHeight) { store.invalidate() }
            }
            LabeledContent("Tracking") {
                Slider(value: $layer.text.tracking, in: -20...60)
                    .onChange(of: layer.text.tracking) { store.invalidate() }
            }
        }
    }

    private func loadFromLayer() {
        hasLoaded = false
        let loaded: NSAttributedString
        if let data = layer.text.rtfData, data.count > 0,
           let attr = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil),
           attr.length > 0 {
            loaded = attr
        } else {
            let fallback = layer.text.string.isEmpty ? "Text" : layer.text.string
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.white
            ]
            loaded = NSAttributedString(string: fallback, attributes: attrs)
        }
        attributedText = loaded
        // Push the loaded content INTO the editor. RichTextKit's documentation
        // explicitly states that changing the `text` binding does not update
        // the editor — you have to drive it through the context's action publisher.
        richContext.actionPublisher.send(.setAttributedString(loaded))
        loadedLayerID = layer.id
        DispatchQueue.main.async {
            hasLoaded = true
        }
    }

    private func applyInlineColor(_ nsColor: NSColor) {
        guard let view = textViewProxy.view as? NSTextView,
              let storage = view.textStorage else {
            tlog("applyInlineColor: no text storage")
            return
        }
        var range = view.selectedRange()
        if range.length == 0 { range = savedSelection }
        guard range.length > 0,
              range.location + range.length <= storage.length else {
            tlog("applyInlineColor: no valid selection (view=\(view.selectedRange()), saved=\(savedSelection))")
            return
        }
        storage.addAttribute(.foregroundColor, value: nsColor, range: range)
        let updated = NSAttributedString(attributedString: storage)
        attributedText = updated
        tlog("applyInlineColor: applied \(nsColor.hexString) to range \(range)")
    }

    private func saveToLayer() {
        guard hasLoaded else {
            tlog("saveToLayer: skipped (not loaded yet)")
            return
        }
        guard loadedLayerID == layer.id else {
            tlog("saveToLayer: skipped (layer id mismatch)")
            return
        }
        let plain = attributedText.string
        if plain.isEmpty && !layer.text.string.isEmpty {
            tlog("saveToLayer: skipped (editor empty, layer non-empty)")
            return
        }

        // Count explicit foreground colors so we can verify attributes are saved.
        var colorCount = 0
        attributedText.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: attributedText.length)) { val, _, _ in
            if val != nil { colorCount += 1 }
        }

        let full = NSRange(location: 0, length: attributedText.length)
        if plain != layer.text.string { layer.text.string = plain }
        if let rtf = try? attributedText.data(
            from: full,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
            layer.text.rtfData = rtf
            tlog("saveToLayer: \(plain.count) chars, \(colorCount) color runs, \(rtf.count) rtf bytes")
        }
        store.invalidate()
    }
}

private struct StyleButton: View {
    let label: String
    @Binding var isOn: Bool
    var bold: Bool = false
    var italic: Bool = false
    var underline: Bool = false
    var strikethrough: Bool = false

    init(_ label: String, isOn: Binding<Bool>, bold: Bool = false, italic: Bool = false, underline: Bool = false, strikethrough: Bool = false) {
        self.label = label
        self._isOn = isOn
        self.bold = bold; self.italic = italic; self.underline = underline; self.strikethrough = strikethrough
    }

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Text(label)
                .font(.system(size: 12, weight: bold ? .bold : .regular, design: .default))
                .italic(italic)
                .underline(underline)
                .strikethrough(strikethrough)
                .frame(width: 28, height: 22)
                .background(RoundedRectangle(cornerRadius: 5)
                    .fill(isOn ? Color.accentColor.opacity(0.25) : Color.black.opacity(0.15)))
                .foregroundStyle(isOn ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

private struct SmartObjectPanel: View {
    @Environment(DocumentStore.self) private var store
    @Bindable var layer: PXLayer
    @State private var isRemovingBG: Bool = false

    @MainActor
    private func removeBG(layer: PXLayer) async {
        guard let smart = layer.smart, let cg = SmartObjectEngine.loadSource(smart) else {
            NSSound.beep(); return
        }
        isRemovingBG = true
        defer { isRemovingBG = false }
        do {
            store.checkpoint("Remove Background")
            let cutout = try await BackgroundRemover.remove(cg)
            if let png = LayerSnapshot.encodePNG(cutout) {
                layer.smart?.sourceBytes = png
                layer.smart?.sourceFormat = "png"
                store.invalidate()
            }
        } catch {
            NSSound.beep()
            terr("Remove BG (inspector) failed: \(error)")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let smart = layer.smart {
                HStack {
                    Text("Source:")
                        .foregroundStyle(.secondary).font(.caption)
                    Text(smart.sourcePath ?? "<embedded>")
                        .font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                }
                HStack {
                    Text("\(smart.pixelWidth) × \(smart.pixelHeight) px")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Edit in…") { store.openSmartLayerInExternalEditor(layer) }
                        .buttonStyle(.borderless).font(.caption)
                }
            }
            LabeledContent("Scale X") {
                Slider(value: Binding(
                    get: { layer.smart?.scaleX ?? 1 },
                    set: { layer.smart?.scaleX = $0; store.invalidate() }
                ), in: 0.05...8)
            }
            LabeledContent("Scale Y") {
                Slider(value: Binding(
                    get: { layer.smart?.scaleY ?? 1 },
                    set: { layer.smart?.scaleY = $0; store.invalidate() }
                ), in: 0.05...8)
            }
            LabeledContent("Rotation") {
                Slider(value: Binding(
                    get: { layer.smart?.rotationDeg ?? 0 },
                    set: { layer.smart?.rotationDeg = $0; store.invalidate() }
                ), in: -180...180)
            }
            HStack {
                Toggle("Flip H", isOn: Binding(
                    get: { layer.smart?.flipH ?? false },
                    set: { layer.smart?.flipH = $0; store.invalidate() }
                ))
                Toggle("Flip V", isOn: Binding(
                    get: { layer.smart?.flipV ?? false },
                    set: { layer.smart?.flipV = $0; store.invalidate() }
                ))
            }
            Text("Double-click the canvas to open the source in its default editor. Saving there updates this layer live.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct CutoutPanel: View {
    @Environment(DocumentStore.self) private var store
    @Bindable var layer: PXLayer
    @State private var isRemovingBG: Bool = false

    @MainActor
    private func removeBG() async {
        guard let smart = layer.smart, let cg = SmartObjectEngine.loadSource(smart) else {
            NSSound.beep(); return
        }
        isRemovingBG = true
        defer { isRemovingBG = false }
        do {
            store.checkpoint("Remove Background")
            let cutout = try await BackgroundRemover.remove(cg)
            if let png = LayerSnapshot.encodePNG(cutout) {
                layer.smart?.sourceBytes = png
                layer.smart?.sourceFormat = "png"
                store.invalidate()
            }
        } catch {
            NSSound.beep()
            terr("Cutout Remove BG failed: \(error)")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    Task { @MainActor in await removeBG() }
                } label: {
                    Label("Remove Background", systemImage: "person.crop.rectangle.stack")
                }
                .disabled(isRemovingBG)
                if isRemovingBG { ProgressView().controlSize(.small) }
                Spacer()
            }
            Text("On-device Vision segmentation. Run it, then fine-tune the edges below.")
                .font(.caption).foregroundStyle(.secondary)

            Divider().padding(.vertical, 2)

            LabeledContent("Edge Offset") {
                HStack {
                    Slider(value: Binding(
                        get: { layer.smart?.edgeOffset ?? 0 },
                        set: { layer.smart?.edgeOffset = $0; store.invalidate() }
                    ), in: -20...20)
                    Text(String(format: "%+.0f", layer.smart?.edgeOffset ?? 0))
                        .font(.caption.monospacedDigit()).frame(width: 32, alignment: .trailing)
                }
            }
            LabeledContent("Feather") {
                HStack {
                    Slider(value: Binding(
                        get: { layer.smart?.edgeFeather ?? 0 },
                        set: { layer.smart?.edgeFeather = $0; store.invalidate() }
                    ), in: 0...20)
                    Text(String(format: "%.1f", layer.smart?.edgeFeather ?? 0))
                        .font(.caption.monospacedDigit()).frame(width: 32, alignment: .trailing)
                }
            }
            LabeledContent("Threshold") {
                HStack {
                    Slider(value: Binding(
                        get: { layer.smart?.edgeThreshold ?? 0 },
                        set: { layer.smart?.edgeThreshold = $0; store.invalidate() }
                    ), in: 0...1)
                    Text(String(format: "%.0f%%", (layer.smart?.edgeThreshold ?? 0) * 100))
                        .font(.caption.monospacedDigit()).frame(width: 40, alignment: .trailing)
                }
            }
            Text("Offset grows (+) / shrinks (−) the subject. Feather softens the outline. Threshold hardens the fringe.")
                .font(.caption).foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Reset Edges") {
                    store.checkpoint("Reset Edge Cleanup")
                    layer.smart?.edgeOffset = 0
                    layer.smart?.edgeFeather = 0
                    layer.smart?.edgeThreshold = 0
                    store.invalidate()
                }
                .buttonStyle(.borderless).font(.caption)
            }
        }
    }
}

private struct SolidEditorPanel: View {
    @Environment(DocumentStore.self) private var store
    @Bindable var layer: PXLayer
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Color") {
                ColorPicker("", selection: Binding(
                    get: { layer.solid.color.swiftUIColor },
                    set: { layer.solid.color = ColorRGB($0.asNSColor); store.invalidate() }
                )).labelsHidden()
            }
            Text("Tip: set layer Blend (in LAYER) to Multiply for a vignette or Screen for a warm color cast.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct GradientEditorPanel: View {
    @Environment(DocumentStore.self) private var store
    @Bindable var layer: PXLayer
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Type") {
                Picker("", selection: $layer.gradient.kind) {
                    Text("Linear").tag("linear"); Text("Radial").tag("radial")
                }.pickerStyle(.segmented).labelsHidden()
                .onChange(of: layer.gradient.kind) { store.invalidate() }
            }
            LabeledContent("Color 1") {
                ColorPicker("", selection: Binding(
                    get: { layer.gradient.c1.swiftUIColor },
                    set: { layer.gradient.c1 = ColorRGB($0.asNSColor); store.invalidate() }
                )).labelsHidden()
            }
            LabeledContent("Color 2") {
                ColorPicker("", selection: Binding(
                    get: { layer.gradient.c2.swiftUIColor },
                    set: { layer.gradient.c2 = ColorRGB($0.asNSColor); store.invalidate() }
                )).labelsHidden()
            }
            LabeledContent("Angle") {
                Slider(value: $layer.gradient.angle, in: 0...360).onChange(of: layer.gradient.angle) { store.invalidate() }
            }
            if layer.gradient.kind == "radial" {
                LabeledContent("Radius") {
                    Slider(value: $layer.gradient.radius, in: 0.05...2).onChange(of: layer.gradient.radius) { store.invalidate() }
                }
            }
        }
    }
}
