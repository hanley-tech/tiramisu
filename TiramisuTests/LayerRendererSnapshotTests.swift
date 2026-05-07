import XCTest
import SnapshotTesting
import CoreGraphics
import AppKit
@testable import Tiramisu

/// Visual regression tests for LayerRenderer. Uses pointfreeco/swift-snapshot-testing
/// to record golden images on first run, then pixel-diff every subsequent run.
///
/// On first run: tests fail and the rendered output is saved to
/// `__Snapshots__/LayerRendererSnapshotTests/<test>.png`. Re-run to lock the
/// golden in. After that, any pixel divergence against the golden fails the
/// test and writes a diff alongside the result.
///
/// Goldens are committed to git. A failure here means either:
///   1. You changed the renderer intentionally — delete the matching .png
///      under __Snapshots__/ and re-run to record a new golden.
///   2. You changed the renderer unintentionally — investigate.
@MainActor
final class LayerRendererSnapshotTests: XCTestCase {

    /// Renders a 200×200 canvas with a single solid cocoa layer covering the
    /// entire canvas. The simplest possible composite path — if this breaks,
    /// the renderer is fundamentally broken.
    func testSolidLayerFillsCanvas() throws {
        let store = DocumentStore()
        store.canvasSize = CGSize(width: 200, height: 200)
        store.backgroundColor = .white

        let layer = PXLayer(name: "solid cocoa", kind: .solid)
        layer.solid = SolidContent(color: ColorRGB(r: 74.0/255.0, g: 44.0/255.0, b: 26.0/255.0))
        store.layers = [layer]

        guard let cg = LayerRenderer.composite(store: store) else {
            XCTFail("LayerRenderer.composite returned nil for a basic solid layer")
            return
        }
        XCTAssertEqual(cg.width, 200, "Canvas width mismatch")
        XCTAssertEqual(cg.height, 200, "Canvas height mismatch")

        let nsImage = NSImage(cgImage: cg, size: NSSize(width: 200, height: 200))
        assertSnapshot(of: nsImage, as: .image(precision: 0.99))
    }

    /// Renders a 200×200 canvas with a warm-gradient layer. Catches regressions
    /// in the gradient renderer's color stops + angle.
    func testGradientLayer() throws {
        let store = DocumentStore()
        store.canvasSize = CGSize(width: 200, height: 200)
        store.backgroundColor = .white

        let layer = PXLayer(name: "warm gradient", kind: .gradient)
        layer.gradient.kind = "linear"
        layer.gradient.c1 = ColorRGB(r: 251.0/255.0, g: 243.0/255.0, b: 226.0/255.0)
        layer.gradient.s1 = 0
        layer.gradient.c2 = ColorRGB(r: 212.0/255.0, g: 130.0/255.0, b: 59.0/255.0)
        layer.gradient.s2 = 1
        layer.gradient.angle = 135
        store.layers = [layer]

        guard let cg = LayerRenderer.composite(store: store) else {
            XCTFail("LayerRenderer.composite returned nil for gradient layer")
            return
        }
        XCTAssertEqual(cg.width, 200)
        XCTAssertEqual(cg.height, 200)

        let nsImage = NSImage(cgImage: cg, size: NSSize(width: 200, height: 200))
        assertSnapshot(of: nsImage, as: .image(precision: 0.99))
    }
}
