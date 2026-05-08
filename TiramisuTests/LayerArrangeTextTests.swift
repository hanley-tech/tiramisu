import Testing
import Foundation
import CoreGraphics
@testable import Tiramisu

/// Unit-tests the text-alignment math added in the inspector-redesign branch.
/// `LayerArrange.align` for text layers writes an absolute `layer.offset`
/// derived from canvas + cached text bounds, so the same anchor produces
/// the same result whether or not a render has happened in between.
@MainActor
@Suite("LayerArrange — text alignment")
struct LayerArrangeTextTests {

    private func makeStore(canvas: CGSize = CGSize(width: 1280, height: 720)) -> DocumentStore {
        let s = DocumentStore()
        s.canvasSize = canvas
        return s
    }

    private func makeTextLayer(in store: DocumentStore, boundsW: CGFloat = 600, boundsH: CGFloat = 200) -> PXLayer {
        let l = PXLayer(name: "Text", kind: .text)
        l.text.string = "EPIC TITLE"
        // Pretend the renderer already produced this rect — our align path
        // reads `lastRenderedBounds` to size the text but recomputes offset
        // absolutely (so stale bounds don't drift consecutive aligns).
        l.text.lastRenderedBounds = CGRect(x: 0, y: 0, width: boundsW, height: boundsH)
        store.layers = [l]
        store.activeLayerID = l.id
        return l
    }

    @Test("Center anchor produces zero offset")
    func center() {
        let s = makeStore()
        let l = makeTextLayer(in: s)
        LayerArrange.align(s, to: .center)
        #expect(l.offset.width == 0)
        #expect(l.offset.height == 0)
    }

    @Test("middleLeft pins the text left-edge to canvas left")
    func middleLeft() {
        let s = makeStore()
        let l = makeTextLayer(in: s)  // bounds 600 wide
        LayerArrange.align(s, to: .middleLeft)
        // Target center.x = boundsW/2 = 300; offset.width = 300 - canvasW/2 = 300 - 640 = -340
        #expect(l.offset.width == -340)
        #expect(l.offset.height == 0)
    }

    @Test("middleRight pins the text right-edge to canvas right")
    func middleRight() {
        let s = makeStore()
        let l = makeTextLayer(in: s)
        LayerArrange.align(s, to: .middleRight)
        // Target center.x = canvasW - boundsW/2 = 1280 - 300 = 980; offset = 980 - 640 = 340
        #expect(l.offset.width == 340)
        #expect(l.offset.height == 0)
    }

    @Test("topCenter places text top at canvas top (negative offset.height)")
    func topCenter() {
        let s = makeStore()
        let l = makeTextLayer(in: s)  // bounds 200 tall
        LayerArrange.align(s, to: .topCenter)
        // Target center.y = boundsH/2 = 100; offset.height = 100 - canvasH/2 = 100 - 360 = -260
        #expect(l.offset.width == 0)
        #expect(l.offset.height == -260)
    }

    @Test("bottomCenter places text bottom at canvas bottom (positive offset.height)")
    func bottomCenter() {
        let s = makeStore()
        let l = makeTextLayer(in: s)
        LayerArrange.align(s, to: .bottomCenter)
        // Target center.y = canvasH - boundsH/2 = 720 - 100 = 620; offset = 620 - 360 = 260
        #expect(l.offset.width == 0)
        #expect(l.offset.height == 260)
    }

    @Test("Consecutive aligns don't drift (stale-bounds bug is fixed)")
    func noDriftBetweenConsecutiveAligns() {
        let s = makeStore()
        let l = makeTextLayer(in: s)
        // Apply middleLeft, then center. Pre-fix, center would no-op
        // because lastRenderedBounds.midX was stale (still at canvas/2),
        // so the delta math computed dx=0. Post-fix uses absolute math.
        LayerArrange.align(s, to: .middleLeft)
        LayerArrange.align(s, to: .center)
        #expect(l.offset.width == 0, "center after middleLeft should produce 0 offset")
        #expect(l.offset.height == 0)
    }

    @Test("canAlign is true for text layers with rendered bounds")
    func canAlignTextWithBounds() {
        let s = makeStore()
        _ = makeTextLayer(in: s)
        #expect(LayerArrange.canAlign(s) == true)
    }

    @Test("canAlign is false for text layers that haven't rendered")
    func canAlignTextNoBounds() {
        let s = makeStore()
        let l = PXLayer(name: "Empty", kind: .text)
        l.text.lastRenderedBounds = .zero
        s.layers = [l]
        s.activeLayerID = l.id
        #expect(LayerArrange.canAlign(s) == false)
    }

    @Test("canAlign is false for gradient/solid layers")
    func canAlignGradient() {
        let s = makeStore()
        let l = PXLayer(name: "Gradient", kind: .gradient)
        s.layers = [l]
        s.activeLayerID = l.id
        #expect(LayerArrange.canAlign(s) == false)
    }

    @Test("canScale is smart-only (text uses font-size, not image scale)")
    func canScaleTextLayer() {
        let s = makeStore()
        _ = makeTextLayer(in: s)
        #expect(LayerArrange.canScale(s) == false)
    }

    @Test("fitTextWidth scales fontSize so text width matches canvas")
    func fitTextWidth() {
        let s = makeStore()
        let l = makeTextLayer(in: s, boundsW: 600)  // current width: 600
        l.text.fontSize = 200
        LayerArrange.fitTextWidth(s)
        // Scale factor = canvas/bounds = 1280/600 = 2.133...
        // newFontSize = 200 * 2.133 = 426.6, clamped to range 8...600
        #expect(l.text.fontSize > 400 && l.text.fontSize < 430)
    }

    @Test("resetTextSize returns fontSize to the model default (220)")
    func resetTextSize() {
        let s = makeStore()
        let l = makeTextLayer(in: s)
        l.text.fontSize = 88
        LayerArrange.resetTextSize(s)
        #expect(l.text.fontSize == 220)
    }
}
