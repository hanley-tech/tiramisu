import SwiftUI

/// Photoshop-style horizontal options bar that sits above the canvas.
/// Content is contextual to the active tool.
struct ToolOptionsBar: View {
    @Environment(DocumentStore.self) private var store

    var body: some View {
        HStack(spacing: 10) {
            switch store.tool {
            case .move:
                MoveToolOptions()
            case .marquee:
                MarqueeToolOptions()
            default:
                Text(store.tool.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct MoveToolOptions: View {
    @Environment(DocumentStore.self) private var store

    private var hasSmart: Bool { store.activeLayer?.smart != nil }

    var body: some View {
        Group {
            // Alignment (canvas as the alignment target).
            HStack(spacing: 2) {
                AlignBtn("align.horizontal.left", "Align Left Edge")        { LayerArrange.align(store, to: .middleLeft) }
                AlignBtn("align.horizontal.center", "Align Horizontal Center") { LayerArrange.align(store, to: .center) }
                AlignBtn("align.horizontal.right", "Align Right Edge")      { LayerArrange.align(store, to: .middleRight) }
                Divider().frame(height: 16).padding(.horizontal, 4)
                AlignBtn("align.vertical.top", "Align Top Edge")            { LayerArrange.align(store, to: .topCenter) }
                AlignBtn("align.vertical.center", "Align Vertical Center")  { LayerArrange.align(store, to: .center) }
                AlignBtn("align.vertical.bottom", "Align Bottom Edge")      { LayerArrange.align(store, to: .bottomCenter) }
            }
            .disabled(!hasSmart)

            Divider().frame(height: 20)

            // Sizing.
            Button("Fit")  { LayerArrange.fitToCanvas(store) }
                .help("Scale to fit inside canvas (⌘⌥F)")
                .disabled(!hasSmart)
            Button("Fill") { LayerArrange.fillCanvas(store) }
                .help("Scale to cover canvas (⌘⌥⇧F)")
                .disabled(!hasSmart)
            Button("1:1")  { LayerArrange.resetScale(store) }
                .help("Reset scale to 100% (⌘⌥0)")
                .disabled(!hasSmart)

            Spacer()

            if !hasSmart {
                Text(store.activeLayer == nil ? "No layer selected" : "Layer is not a Smart Object — Place Image… to align")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .controlSize(.small)
    }
}

private struct AlignBtn: View {
    let symbol: String
    let tip: String
    let action: () -> Void

    init(_ symbol: String, _ tip: String, action: @escaping () -> Void) {
        self.symbol = symbol
        self.tip = tip
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 24, height: 22)
        }
        .buttonStyle(.borderless)
        .help(tip)
    }
}

private struct MarqueeToolOptions: View {
    @Environment(DocumentStore.self) private var store

    var body: some View {
        Text("Drag to draw a selection · ⌘⇧G to Generative Fill inside it")
            .font(.caption)
            .foregroundStyle(.secondary)
        Spacer()
        if store.selectionRect != nil {
            Button("Deselect") {
                store.selectionRect = nil
                store.invalidate()
            }
            .controlSize(.small)
        }
    }
}
