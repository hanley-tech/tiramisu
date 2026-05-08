import SwiftUI
import AppKit

struct TransformOverlay: View {
    @Environment(DocumentStore.self) private var store
    let docToView: CGFloat
    let imageOrigin: CGPoint    // top-left of the canvas image in this view's coords

    @State private var dragStart: DragStart?
    @State private var missStart: CGPoint?

    private struct DragStart {
        enum Kind { case move, cornerTL, cornerTR, cornerBL, cornerBR, rotate }
        let kind: Kind
        let startCenter: CGPoint
        let startScaleX: Double
        let startScaleY: Double
        let startRotation: Double
        let startMouseDoc: CGPoint
    }

    var body: some View {
        Canvas { ctx, size in
            // Marquee selection — render the active selection as marching ants.
            if let sel = store.selectionRect {
                let r = CGRect(x: sel.minX * docToView + imageOrigin.x,
                               y: sel.minY * docToView + imageOrigin.y,
                               width: sel.width * docToView,
                               height: sel.height * docToView)
                ctx.stroke(Path(r),
                           with: .color(.white),
                           style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                ctx.stroke(Path(r),
                           with: .color(.black),
                           style: StrokeStyle(lineWidth: 1.5, dash: [5, 4], dashPhase: 4))
            }

            guard let layer = store.activeLayer else { return }

            if store.tool == .move {
                if let smart = layer.smart {
                    drawBBox(ctx, bboxDoc(smart: smart))
                } else if layer.kind == .text, let b = textBBoxDoc(layer: layer) {
                    drawBBox(ctx, b)
                }
            }

            if store.tool == .relight && layer.relight.enabled {
                // Draw the key-light position as a ringed target at the UV center.
                let px = imageOrigin.x + layer.relight.position.x * store.canvasSize.width * docToView
                let py = imageOrigin.y + layer.relight.position.y * store.canvasSize.height * docToView
                let ringR = max(10, layer.relight.radius * max(store.canvasSize.width, store.canvasSize.height) * docToView * 0.45)
                ctx.stroke(Path(ellipseIn: CGRect(x: px - ringR, y: py - ringR, width: ringR * 2, height: ringR * 2)),
                           with: .color(.yellow.opacity(0.7)),
                           style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                // Crosshair
                ctx.stroke(Path { p in
                    p.move(to: CGPoint(x: px - 12, y: py))
                    p.addLine(to: CGPoint(x: px + 12, y: py))
                    p.move(to: CGPoint(x: px, y: py - 12))
                    p.addLine(to: CGPoint(x: px, y: py + 12))
                }, with: .color(.yellow), lineWidth: 1.5)
                let hub = CGRect(x: px - 4, y: py - 4, width: 8, height: 8)
                ctx.fill(Path(ellipseIn: hub), with: .color(.yellow))
            }
        }
        .contentShape(Rectangle())
        .gesture(dragGesture)
    }

    private func bboxDoc(smart: SmartSource) -> CGRect {
        let w = Double(smart.pixelWidth) * abs(smart.scaleX)
        let h = Double(smart.pixelHeight) * abs(smart.scaleY)
        return CGRect(x: smart.centerX - w / 2,
                      y: smart.centerY - h / 2,
                      width: w, height: h)
    }

    private func textBBoxDoc(layer: PXLayer) -> CGRect? {
        var b = layer.text.lastRenderedBounds
        guard b.width > 0 && b.height > 0 else { return nil }
        // lastRenderedBounds is stored assuming anchor = (0.5, 0.5) AND
        // offset = (0, 0). The renderer applies both as a translation at
        // composite time (see LayerRenderer.composite), so we have to
        // mirror that here so the bbox tracks where the text actually drew.
        let dx = (layer.text.anchorX - 0.5) * store.canvasSize.width + layer.offset.width
        let dy = (layer.text.anchorY - 0.5) * store.canvasSize.height + layer.offset.height
        b.origin.x += dx
        b.origin.y += dy
        return b
    }

    private func drawBBox(_ ctx: GraphicsContext, _ bDoc: CGRect) {
        let rect = CGRect(x: bDoc.minX * docToView + imageOrigin.x,
                          y: bDoc.minY * docToView + imageOrigin.y,
                          width: bDoc.width * docToView,
                          height: bDoc.height * docToView)
        ctx.stroke(Path(rect),
                   with: .color(.accentColor),
                   style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        for pt in handlePoints(in: rect) {
            let r = CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10)
            ctx.fill(Path(ellipseIn: r), with: .color(.white))
            ctx.stroke(Path(ellipseIn: r), with: .color(.accentColor), lineWidth: 1.5)
        }
    }

    private func handlePoints(in rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY),
        ]
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let docP = CGPoint(x: (value.location.x - imageOrigin.x) / docToView,
                                   y: (value.location.y - imageOrigin.y) / docToView)

                if store.tool == .marquee {
                    // Drag draws a selection rect. Start point = where missStart was set.
                    if missStart == nil { missStart = value.location }
                    let startDoc = CGPoint(
                        x: ((missStart?.x ?? value.location.x) - imageOrigin.x) / docToView,
                        y: ((missStart?.y ?? value.location.y) - imageOrigin.y) / docToView
                    )
                    let x1 = min(startDoc.x, docP.x), y1 = min(startDoc.y, docP.y)
                    let x2 = max(startDoc.x, docP.x), y2 = max(startDoc.y, docP.y)
                    store.selectionRect = CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1)
                    return
                }

                if store.tool == .relight {
                    if let layer = store.activeLayer {
                        if dragStart == nil { store.checkpoint("Move Key Light") }
                        let u = max(0, min(1, docP.x / store.canvasSize.width))
                        let v = max(0, min(1, docP.y / store.canvasSize.height))
                        layer.relight.position = CGPoint(x: u, y: v)
                        if !layer.relight.enabled { layer.relight.enabled = true }
                        // Mark as "in gesture" so onEnded knows not to deselect.
                        dragStart = dragStart ?? DragStart(kind: .move,
                                                          startCenter: .zero,
                                                          startScaleX: 0, startScaleY: 0,
                                                          startRotation: 0,
                                                          startMouseDoc: docP)
                        store.invalidate()
                    }
                    return
                }

                guard store.tool == .move else { return }

                // If we haven't started manipulating yet, figure out WHAT the user clicked.
                if dragStart == nil {
                    if let active = store.activeLayer {
                        // Smart layer: handles + bbox
                        if let smart = active.smart,
                           let kind = hitTestOrNil(smart: smart, atDoc: docP) {
                            store.checkpoint(kind == .move ? "Move" : "Scale")
                            dragStart = makeStart(kind: kind, smart: smart, at: docP)
                            return
                        }
                        // Text layer: bbox from cached render
                        if active.kind == .text,
                           let kind = hitTestTextOrNil(layer: active, atDoc: docP) {
                            store.checkpoint(kind == .move ? "Move Text" : "Resize Text")
                            dragStart = DragStart(
                                kind: kind,
                                startCenter: CGPoint(x: active.text.anchorX * store.canvasSize.width,
                                                     y: active.text.anchorY * store.canvasSize.height),
                                startScaleX: active.text.fontSize,
                                startScaleY: active.text.fontSize,
                                startRotation: 0,
                                startMouseDoc: docP
                            )
                            return
                        }
                    }
                    // Scan all layers top-to-bottom to pick one on click.
                    for L in store.layers.reversed() {
                        guard L.visible else { continue }
                        if let smart = L.smart,
                           bboxDoc(smart: smart).insetBy(dx: -6 / docToView, dy: -6 / docToView).contains(docP) {
                            store.activeLayerID = L.id
                            store.checkpoint("Move")
                            dragStart = makeStart(kind: .move, smart: smart, at: docP)
                            return
                        }
                        if L.kind == .text,
                           let tb = textBBoxDoc(layer: L),
                           tb.insetBy(dx: -6 / docToView, dy: -6 / docToView).contains(docP) {
                            store.activeLayerID = L.id
                            store.checkpoint("Move Text")
                            dragStart = DragStart(
                                kind: .move,
                                startCenter: CGPoint(x: L.text.anchorX * store.canvasSize.width,
                                                     y: L.text.anchorY * store.canvasSize.height),
                                startScaleX: L.text.fontSize,
                                startScaleY: L.text.fontSize,
                                startRotation: 0,
                                startMouseDoc: docP
                            )
                            return
                        }
                    }
                    if missStart == nil { missStart = value.location }
                    return
                }

                // Apply the in-progress drag.
                guard let layer = store.activeLayer, let s = dragStart else { return }
                let dx = docP.x - s.startMouseDoc.x
                let dy = docP.y - s.startMouseDoc.y

                // Text layer mutations
                if layer.kind == .text && layer.smart == nil {
                    switch s.kind {
                    case .move:
                        let nx = s.startCenter.x + dx
                        let ny = s.startCenter.y + dy
                        layer.text.anchorX = nx / store.canvasSize.width
                        layer.text.anchorY = ny / store.canvasSize.height
                    case .cornerTL, .cornerTR, .cornerBL, .cornerBR:
                        // Resize font size based on distance-from-center ratio.
                        let startR = max(hypot(s.startMouseDoc.x - s.startCenter.x,
                                               s.startMouseDoc.y - s.startCenter.y), 0.0001)
                        let newR = hypot(docP.x - s.startCenter.x, docP.y - s.startCenter.y)
                        let r = newR / startR
                        layer.text.fontSize = max(6, min(1200, s.startScaleX * Double(r)))
                    case .rotate: break
                    }
                    store.invalidate()
                    return
                }

                // Smart layer mutations
                guard var smart = layer.smart else { return }
                switch s.kind {
                case .move:
                    smart.centerX = s.startCenter.x + dx
                    smart.centerY = s.startCenter.y + dy
                case .cornerTL, .cornerTR, .cornerBL, .cornerBR:
                    let startDx = s.startMouseDoc.x - s.startCenter.x
                    let startDy = s.startMouseDoc.y - s.startCenter.y
                    let newDx = docP.x - s.startCenter.x
                    let newDy = docP.y - s.startCenter.y
                    let shift = NSEvent.modifierFlags.contains(.shift)
                    if shift {
                        let rx = startDx == 0 ? 1 : newDx / startDx
                        let ry = startDy == 0 ? 1 : newDy / startDy
                        smart.scaleX = max(0.02, abs(s.startScaleX * Double(rx)))
                        smart.scaleY = max(0.02, abs(s.startScaleY * Double(ry)))
                    } else {
                        let startR = max(hypot(startDx, startDy), 0.0001)
                        let newR = hypot(newDx, newDy)
                        let r = newR / startR
                        smart.scaleX = max(0.02, s.startScaleX * Double(r))
                        smart.scaleY = max(0.02, s.startScaleY * Double(r))
                    }
                case .rotate:
                    break
                }
                layer.smart = smart
                store.invalidate()
            }
            .onEnded { value in
                if store.tool == .marquee {
                    // Tap with no drag clears the selection.
                    if let start = missStart, hypot(value.location.x - start.x, value.location.y - start.y) < 4 {
                        store.selectionRect = nil
                    }
                    missStart = nil
                    return
                }
                if dragStart == nil, let start = missStart {
                    let dx = value.location.x - start.x
                    let dy = value.location.y - start.y
                    if hypot(dx, dy) < 4 {
                        store.activeLayerID = nil
                    }
                }
                dragStart = nil
                missStart = nil
            }
    }

    private func makeStart(kind: DragStart.Kind, smart: SmartSource, at docP: CGPoint) -> DragStart {
        DragStart(
            kind: kind,
            startCenter: CGPoint(x: smart.centerX, y: smart.centerY),
            startScaleX: smart.scaleX,
            startScaleY: smart.scaleY,
            startRotation: smart.rotationDeg,
            startMouseDoc: docP
        )
    }

    private func hitTestTextOrNil(layer: PXLayer, atDoc p: CGPoint) -> DragStart.Kind? {
        guard let b = textBBoxDoc(layer: layer) else { return nil }
        let hitRadius: CGFloat = 10 / docToView
        let corners: [(CGPoint, DragStart.Kind)] = [
            (CGPoint(x: b.minX, y: b.minY), .cornerTL),
            (CGPoint(x: b.maxX, y: b.minY), .cornerTR),
            (CGPoint(x: b.minX, y: b.maxY), .cornerBL),
            (CGPoint(x: b.maxX, y: b.maxY), .cornerBR),
        ]
        for (pt, kind) in corners {
            if hypot(p.x - pt.x, p.y - pt.y) <= hitRadius { return kind }
        }
        if b.insetBy(dx: -hitRadius, dy: -hitRadius).contains(p) { return .move }
        return nil
    }

    private func hitTestOrNil(smart: SmartSource, atDoc p: CGPoint) -> DragStart.Kind? {
        let b = bboxDoc(smart: smart)
        let hitRadius: CGFloat = 10 / docToView
        let corners: [(CGPoint, DragStart.Kind)] = [
            (CGPoint(x: b.minX, y: b.minY), .cornerTL),
            (CGPoint(x: b.maxX, y: b.minY), .cornerTR),
            (CGPoint(x: b.minX, y: b.maxY), .cornerBL),
            (CGPoint(x: b.maxX, y: b.maxY), .cornerBR),
        ]
        for (pt, kind) in corners {
            if hypot(p.x - pt.x, p.y - pt.y) <= hitRadius { return kind }
        }
        if b.insetBy(dx: -hitRadius, dy: -hitRadius).contains(p) { return .move }
        return nil
    }
}
