import XCTest
import SnapshotTesting
import CoreGraphics
import AppKit
@testable import Tiramisu

/// Visual regression for the most-used layer styles + opacity composition.
/// Each test renders a deliberately simple fixture so the effect is
/// unambiguous in the golden image — a regression in the style renderer
/// will produce a clearly different picture.
@MainActor
final class LayerStyleSnapshotTests: XCTestCase {

    /// Renders bold white text with a drop shadow over a light canvas.
    /// The shadow's distance, angle, blur, and opacity are visible in the
    /// golden — any change to those defaults or the shadow rasterizer
    /// produces an obvious diff.
    func testDropShadow() throws {
        let store = DocumentStore()
        store.canvasSize = CGSize(width: 320, height: 180)
        store.backgroundColor = ColorRGB(r: 0.93, g: 0.92, b: 0.88)
        store.layers = []

        let title = PXLayer(name: "shadow text", kind: .text)
        title.text.string = "SHADOW"
        title.text.fontSize = 80
        title.text.weight = 800
        title.text.color = .white
        title.styles.dropShadow.enabled = true
        title.styles.dropShadow.color = .black
        title.styles.dropShadow.opacity = 0.7
        title.styles.dropShadow.distance = 10
        title.styles.dropShadow.angle = 135
        title.styles.dropShadow.blur = 14
        store.layers = [title]

        let cg = LayerRenderer.composite(store: store)!
        let img = NSImage(cgImage: cg, size: NSSize(width: 320, height: 180))
        // Shadow blur uses CIFilter — minor float-drift across macOS minor
        // versions justifies a slightly looser precision.
        assertSnapshot(of: img, as: .image(precision: 0.97))
    }

    /// Renders white text with a black 6pt stroke. Stroke width, color, and
    /// opacity are visible at the edges of every glyph in the golden.
    func testStroke() throws {
        let store = DocumentStore()
        store.canvasSize = CGSize(width: 320, height: 180)
        store.backgroundColor = ColorRGB(r: 0.95, g: 0.95, b: 0.95)
        store.layers = []

        let title = PXLayer(name: "stroked text", kind: .text)
        title.text.string = "STROKE"
        title.text.fontSize = 80
        title.text.weight = 800
        title.text.color = .white
        title.styles.stroke.enabled = true
        title.styles.stroke.color = .black
        title.styles.stroke.size = 6
        title.styles.stroke.opacity = 1
        store.layers = [title]

        let cg = LayerRenderer.composite(store: store)!
        let img = NSImage(cgImage: cg, size: NSSize(width: 320, height: 180))
        assertSnapshot(of: img, as: .image(precision: 0.97))
    }

    /// Renders a solid red layer at 50% opacity over a solid blue background.
    /// The composited result should be a clear mid-purple — proves opacity
    /// math is correct (a regression to "no opacity applied" yields pure
    /// red; "full opacity = transparent" yields pure blue; the correct
    /// value is between).
    func testFiftyPercentOpacityComposition() throws {
        let store = DocumentStore()
        store.canvasSize = CGSize(width: 200, height: 200)
        store.backgroundColor = ColorRGB(r: 0.10, g: 0.30, b: 0.70)
        store.layers = []

        let bg = PXLayer(name: "bg", kind: .solid)
        bg.solid = SolidContent(color: ColorRGB(r: 0.10, g: 0.30, b: 0.70))

        let top = PXLayer(name: "top 50%", kind: .solid)
        top.solid = SolidContent(color: ColorRGB(r: 0.90, g: 0.10, b: 0.10))
        top.opacity = 0.5

        store.layers = [bg, top]

        let cg = LayerRenderer.composite(store: store)!
        let img = NSImage(cgImage: cg, size: NSSize(width: 200, height: 200))
        assertSnapshot(of: img, as: .image(precision: 0.99))
    }
}
