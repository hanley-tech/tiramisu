import SwiftUI

struct ToolOptionsPanel: View {
    @Environment(DocumentStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(store.tool.label, systemImage: store.tool.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            switch store.tool {
            case .pencil, .pen, .eraser:
                BrushControls()
            case .move:
                Text("Drag on canvas to move the active layer. Arrow keys nudge 1 px (⇧ = 10 px).")
                    .font(.caption).foregroundStyle(.secondary)
            case .text:
                Text("Click the canvas to drop a text layer anchor. Edit in the Properties tab.")
                    .font(.caption).foregroundStyle(.secondary)
            case .eyedropper:
                Text("Click a pixel to sample it into Foreground.")
                    .font(.caption).foregroundStyle(.secondary)
            case .relight:
                Text("Drag on canvas to aim the key light. Tune intensity / color in Adjust → Relight.")
                    .font(.caption).foregroundStyle(.secondary)
            case .marquee:
                Text("Drag to draw a selection. Use AI → Generative Fill (⌘⇧G) to regenerate inside the selection.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BrushControls: View {
    @Environment(DocumentStore.self) private var store
    var body: some View {
        LabeledContent("Size") {
            HStack {
                Slider(value: Binding(get: { store.brush.size }, set: { store.brush.size = $0 }), in: 1...400)
                Text("\(Int(store.brush.size))").font(.caption.monospacedDigit()).frame(width: 32, alignment: .trailing)
            }
        }
        LabeledContent("Feather") {
            Slider(value: Binding(get: { store.brush.feather }, set: { store.brush.feather = $0 }), in: 0...1)
        }
        LabeledContent("Opacity") {
            Slider(value: Binding(get: { store.brush.opacity }, set: { store.brush.opacity = $0 }), in: 0.01...1)
        }
        LabeledContent("Flow") {
            Slider(value: Binding(get: { store.brush.flow }, set: { store.brush.flow = $0 }), in: 0.01...1)
        }
    }
}
