import Foundation
import CoreGraphics

@MainActor
enum LayerArrange {
    enum Anchor {
        case topLeft, topCenter, topRight
        case middleLeft, center, middleRight
        case bottomLeft, bottomCenter, bottomRight
    }

    /// True if `align(...)` can operate on the active layer. Smart objects
    /// always qualify; text layers qualify once they've been rendered at
    /// least once (we use the cached `lastRenderedBounds` to know their size).
    static func canAlign(_ store: DocumentStore) -> Bool {
        guard let layer = store.activeLayer else { return false }
        if layer.smart != nil { return true }
        if layer.kind == .text { return layer.text.lastRenderedBounds.width > 0 }
        return false
    }

    /// True for the scale-related ops (fit / fill / 1:1) — those are still
    /// smart-only because they imply image resampling.
    static func canScale(_ store: DocumentStore) -> Bool {
        store.activeLayer?.smart != nil
    }

    /// Legacy alias kept for any callers that expected the old name.
    static func canArrange(_ store: DocumentStore) -> Bool { canAlign(store) }

    static func fitToCanvas(_ store: DocumentStore) {
        guard let layer = store.activeLayer, var smart = layer.smart else { return }
        let canvas = store.canvasSize
        let pw = max(1, Double(smart.pixelWidth))
        let ph = max(1, Double(smart.pixelHeight))
        let s = min(Double(canvas.width) / pw, Double(canvas.height) / ph)
        store.checkpoint("Fit to Canvas")
        smart.scaleX = s; smart.scaleY = s
        smart.centerX = Double(canvas.width) / 2
        smart.centerY = Double(canvas.height) / 2
        layer.smart = smart
        store.invalidate()
    }

    static func fillCanvas(_ store: DocumentStore) {
        guard let layer = store.activeLayer, var smart = layer.smart else { return }
        let canvas = store.canvasSize
        let pw = max(1, Double(smart.pixelWidth))
        let ph = max(1, Double(smart.pixelHeight))
        let s = max(Double(canvas.width) / pw, Double(canvas.height) / ph)
        store.checkpoint("Fill Canvas")
        smart.scaleX = s; smart.scaleY = s
        smart.centerX = Double(canvas.width) / 2
        smart.centerY = Double(canvas.height) / 2
        layer.smart = smart
        store.invalidate()
    }

    static func resetScale(_ store: DocumentStore) {
        guard let layer = store.activeLayer, var smart = layer.smart else { return }
        store.checkpoint("Reset Scale")
        smart.scaleX = 1; smart.scaleY = 1
        layer.smart = smart
        store.invalidate()
    }

    /// Text equivalent of "Fit": scale `fontSize` so the rendered text width
    /// matches the canvas width. Uses the cached `lastRenderedBounds` as the
    /// reference — only meaningful when text has been rendered at least once.
    /// For multi-line text this is approximate; the user can fine-tune via
    /// the Size slider afterwards.
    static func fitTextWidth(_ store: DocumentStore) {
        guard let layer = store.activeLayer, layer.kind == .text else { return }
        let bounds = layer.text.lastRenderedBounds
        guard bounds.width > 0 else { return }
        let cw = Double(store.canvasSize.width)
        let scale = cw / Double(bounds.width)
        store.checkpoint("Fit Text Width")
        layer.text.fontSize = max(8, min(600, layer.text.fontSize * scale))
        store.invalidate()
    }

    /// Text equivalent of "1:1": reset `fontSize` to the model default (220pt).
    static func resetTextSize(_ store: DocumentStore) {
        guard let layer = store.activeLayer, layer.kind == .text else { return }
        store.checkpoint("Reset Text Size")
        layer.text.fontSize = 220
        store.invalidate()
    }

    static func align(_ store: DocumentStore, to anchor: Anchor) {
        guard let layer = store.activeLayer else { return }
        let canvas = store.canvasSize
        let cw = Double(canvas.width)
        let ch = Double(canvas.height)

        // Smart-object path — uses `centerX/centerY` (absolute doc coords).
        if var smart = layer.smart {
            let lw = Double(smart.pixelWidth) * smart.scaleX
            let lh = Double(smart.pixelHeight) * smart.scaleY
            let (cx, cy) = targetCenter(anchor, lw: lw, lh: lh, cw: cw, ch: ch)
            store.checkpoint("Align Layer")
            smart.centerX = cx; smart.centerY = cy
            layer.smart = smart
            store.invalidate()
            return
        }

        // Text path — set `layer.offset` to an ABSOLUTE position derived from
        // canvas size + cached text dimensions. The width/height of the text in
        // `lastRenderedBounds` is stable across alignment changes (only the
        // position changes), so reading them is safe even if a prior align
        // hasn't been re-rendered yet.
        //
        // Renderer (default anchor 0.5, 0.5):
        //   bounds.midX = cw/2 + offset.width        →  offset.width  = targetX - cw/2
        // Empirically, positive `offset.height` moves the text DOWN visually
        // (despite the renderer's `ty = -offset.height` — likely the doc
        // composite is also Y-flipped). So:
        //   offset.height = targetY - ch/2
        if layer.kind == .text {
            let bounds = layer.text.lastRenderedBounds
            guard bounds.width > 0, bounds.height > 0 else {
                tlog("LayerArrange.align: text has no rendered bounds yet — render once first")
                return
            }
            let (tx, ty) = targetCenter(anchor, lw: Double(bounds.width), lh: Double(bounds.height), cw: cw, ch: ch)
            store.checkpoint("Align Layer")
            layer.offset = CGSize(width: tx - cw / 2, height: ty - ch / 2)
            store.invalidate()
            return
        }
        // Gradient / solid layers fill the whole canvas — alignment doesn't apply.
    }

    private static func targetCenter(_ anchor: Anchor, lw: Double, lh: Double, cw: Double, ch: Double) -> (Double, Double) {
        switch anchor {
        case .topLeft:      return (lw / 2,        lh / 2)
        case .topCenter:    return (cw / 2,        lh / 2)
        case .topRight:     return (cw - lw / 2,   lh / 2)
        case .middleLeft:   return (lw / 2,        ch / 2)
        case .center:       return (cw / 2,        ch / 2)
        case .middleRight:  return (cw - lw / 2,   ch / 2)
        case .bottomLeft:   return (lw / 2,        ch - lh / 2)
        case .bottomCenter: return (cw / 2,        ch - lh / 2)
        case .bottomRight:  return (cw - lw / 2,   ch - lh / 2)
        }
    }
}
