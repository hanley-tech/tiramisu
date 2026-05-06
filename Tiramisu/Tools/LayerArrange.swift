import Foundation
import CoreGraphics

@MainActor
enum LayerArrange {
    enum Anchor {
        case topLeft, topCenter, topRight
        case middleLeft, center, middleRight
        case bottomLeft, bottomCenter, bottomRight
    }

    static func canArrange(_ store: DocumentStore) -> Bool {
        store.activeLayer?.smart != nil
    }

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

    static func align(_ store: DocumentStore, to anchor: Anchor) {
        guard let layer = store.activeLayer, var smart = layer.smart else { return }
        let canvas = store.canvasSize
        let lw = Double(smart.pixelWidth) * smart.scaleX
        let lh = Double(smart.pixelHeight) * smart.scaleY
        let cw = Double(canvas.width)
        let ch = Double(canvas.height)
        let cx: Double
        let cy: Double
        switch anchor {
        case .topLeft:      cx = lw / 2;        cy = lh / 2
        case .topCenter:    cx = cw / 2;        cy = lh / 2
        case .topRight:     cx = cw - lw / 2;   cy = lh / 2
        case .middleLeft:   cx = lw / 2;        cy = ch / 2
        case .center:       cx = cw / 2;        cy = ch / 2
        case .middleRight:  cx = cw - lw / 2;   cy = ch / 2
        case .bottomLeft:   cx = lw / 2;        cy = ch - lh / 2
        case .bottomCenter: cx = cw / 2;        cy = ch - lh / 2
        case .bottomRight:  cx = cw - lw / 2;   cy = ch - lh / 2
        }
        store.checkpoint("Align Layer")
        smart.centerX = cx; smart.centerY = cy
        layer.smart = smart
        store.invalidate()
    }
}
