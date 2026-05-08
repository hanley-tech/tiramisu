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
        // Liquid Glass: thin material reads as part of the macOS 26 chrome
        // instead of a flat opaque strip. Falls back to the system bar
        // material on older AppKit if the glass primitive isn't available.
        .background(.bar)
    }
}

private struct MoveToolOptions: View {
    @Environment(DocumentStore.self) private var store

    private var activeKind: LayerKind? { store.activeLayer?.kind }
    private var hasSmart: Bool { store.activeLayer?.smart != nil }

    var body: some View {
        Group {
            // Alignment row — shown whenever the active layer can be aligned
            // (Smart Object or text). Hidden for gradient/solid (those fill
            // the canvas, alignment is meaningless).
            if LayerArrange.canAlign(store) {
                HStack(spacing: 2) {
                    AlignBtn("align.horizontal.left", "Align Left Edge")        { LayerArrange.align(store, to: .middleLeft) }
                    AlignBtn("align.horizontal.center", "Align Horizontal Center") { LayerArrange.align(store, to: .center) }
                    AlignBtn("align.horizontal.right", "Align Right Edge")      { LayerArrange.align(store, to: .middleRight) }
                    Divider().frame(height: 16).padding(.horizontal, 4)
                    AlignBtn("align.vertical.top", "Align Top Edge")            { LayerArrange.align(store, to: .topCenter) }
                    AlignBtn("align.vertical.center", "Align Vertical Center")  { LayerArrange.align(store, to: .center) }
                    AlignBtn("align.vertical.bottom", "Align Bottom Edge")      { LayerArrange.align(store, to: .bottomCenter) }
                }

                Divider().frame(height: 20)
            }

            // Scaling row — swapped based on layer kind. Smart Object gets
            // Fit / Fill / 1:1 (image resampling). Text gets Fit width / Reset
            // size (font scaling). Gradient/solid get nothing.
            if hasSmart {
                Button("Fit")  { LayerArrange.fitToCanvas(store) }
                    .help("Scale to fit inside canvas (⌘⌥F)")
                Button("Fill") { LayerArrange.fillCanvas(store) }
                    .help("Scale to cover canvas (⌘⌥⇧F)")
                Button("1:1")  { LayerArrange.resetScale(store) }
                    .help("Reset scale to 100% (⌘⌥0)")
            } else if activeKind == .text {
                Button("Fit width") { LayerArrange.fitTextWidth(store) }
                    .help("Scale font size so the text spans the canvas width")
                Button("Reset size") { LayerArrange.resetTextSize(store) }
                    .help("Reset font size to default (220pt)")
            }

            Spacer()
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
