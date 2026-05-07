import XCTest
import SnapshotTesting
import CoreGraphics
import AppKit
@testable import Tiramisu

/// Visual regression for text layer rendering. Text is the most user-visible
/// feature in Tiramisu — every demo screenshot shows it — so a regression in
/// the text path (font metrics, alignment, color, weight) would be highly
/// noticeable. The golden under `__Snapshots__/` locks in the canonical
/// rendering of "EPIC TITLE" centered on a dark canvas.
@MainActor
final class TextLayerSnapshotTests: XCTestCase {

    func testHeroText() throws {
        let store = DocumentStore()
        store.canvasSize = CGSize(width: 480, height: 270)
        store.backgroundColor = ColorRGB(r: 0.08, g: 0.08, b: 0.10)
        store.layers = []

        let title = PXLayer(name: "Hero", kind: .text)
        title.text.string = "EPIC\nTITLE"
        title.text.fontName = "System"
        title.text.fontSize = 90
        title.text.weight = 800
        title.text.alignment = "center"
        title.text.lineHeight = 1.0
        title.text.color = .white
        title.text.anchorX = 0.5
        title.text.anchorY = 0.5
        store.layers = [title]

        guard let cg = LayerRenderer.composite(store: store) else {
            XCTFail("LayerRenderer.composite returned nil for text layer")
            return
        }
        XCTAssertEqual(cg.width, 480)
        XCTAssertEqual(cg.height, 270)

        let nsImage = NSImage(cgImage: cg, size: NSSize(width: 480, height: 270))
        // Slightly looser precision than other snapshots — text antialiasing
        // can drift by a few pixels across macOS minor versions / renderers.
        assertSnapshot(of: nsImage, as: .image(precision: 0.97))
    }
}
