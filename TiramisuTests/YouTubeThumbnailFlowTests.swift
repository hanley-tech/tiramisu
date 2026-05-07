import XCTest
import SnapshotTesting
import CoreGraphics
import AppKit
@testable import Tiramisu

/// End-to-end-ish test for the bulletproof YouTube-thumbnail workflow.
/// Exercises the full pipeline that a creator would run by hand:
///
///   1. Set canvas to 1280×720 (YouTube preset)
///   2. Add a gradient background layer
///   3. Add a hero text layer with stroke + outer glow
///   4. Composite via LayerRenderer
///   5. Encode the composite as PNG with NSBitmapImageRep
///   6. Write PNG to disk
///   7. Read it back, assert dimensions and decode-ability
///
/// The only step in the user-facing flow that this test skips is AI
/// background removal, which requires a real subject image and is covered
/// by `BackgroundRemover` itself (Apple Vision framework, no network).
///
/// If any of these steps regresses — the renderer breaks, NSBitmapImageRep
/// can't encode the canvas, the file size is suspiciously tiny, the
/// dimensions don't survive — this test fails and the YT thumbnail flow
/// is no longer bulletproof.
@MainActor
final class YouTubeThumbnailFlowTests: XCTestCase {

    func testFullYouTubeThumbnailFlowRendersAndExports() throws {
        // 1. Canvas at YouTube thumbnail size.
        let store = DocumentStore()
        store.canvasSize = CGSize(width: 1280, height: 720)
        store.backgroundColor = ColorRGB(r: 0.04, g: 0.05, b: 0.10)
        store.layers = []

        // 2. Gradient background layer (purple → magenta diagonal).
        let bg = PXLayer(name: "Background Gradient", kind: .gradient)
        bg.gradient.kind = "linear"
        bg.gradient.angle = 135
        bg.gradient.c1 = ColorRGB(r: 0.34, g: 0.18, b: 0.50)
        bg.gradient.s1 = 0
        bg.gradient.c2 = ColorRGB(r: 0.85, g: 0.20, b: 0.50)
        bg.gradient.s2 = 1
        store.layers.append(bg)

        // 3. Hero text with stroke + outer glow — the typical YT thumbnail look.
        let hero = PXLayer(name: "Hero", kind: .text)
        hero.text.string = "EPIC\nTITLE"
        hero.text.fontName = "System"
        hero.text.fontSize = 240
        hero.text.weight = 800
        hero.text.alignment = "center"
        hero.text.lineHeight = 1.0
        hero.text.color = .white
        hero.text.anchorX = 0.5
        hero.text.anchorY = 0.5
        hero.styles.stroke.enabled = true
        hero.styles.stroke.color = .black
        hero.styles.stroke.size = 8
        hero.styles.outerGlow.enabled = true
        hero.styles.outerGlow.color = ColorRGB(r: 1.0, g: 0.85, b: 0.35)
        hero.styles.outerGlow.size = 60
        hero.styles.outerGlow.opacity = 0.8
        store.layers.append(hero)

        // 4. Composite the canvas.
        guard let cg = LayerRenderer.composite(store: store) else {
            XCTFail("LayerRenderer.composite returned nil for the YT fixture")
            return
        }
        XCTAssertEqual(cg.width, 1280, "YT canvas width must be 1280")
        XCTAssertEqual(cg.height, 720, "YT canvas height must be 720")

        // 5. Encode as PNG via the same path the app uses (AppCommands.exportPNG).
        let rep = NSBitmapImageRep(cgImage: cg)
        rep.size = NSSize(width: cg.width, height: cg.height)
        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            XCTFail("NSBitmapImageRep failed to encode PNG — would surface as a user-facing 'Could not encode PNG' alert")
            return
        }
        XCTAssertGreaterThan(pngData.count, 5_000,
                             "PNG encoded but is suspiciously tiny (\(pngData.count) bytes) — renderer may be producing a blank canvas")

        // 6. Write to disk under a temp path the same way exportPNG does.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tiramisu-yt-flow-\(UUID().uuidString).png")
        try pngData.write(to: tmp, options: .atomic)
        defer { try? FileManager.default.removeItem(at: tmp) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.path))

        // 7. Read it back and confirm decodability + dimensions.
        let loadedData = try Data(contentsOf: tmp)
        XCTAssertEqual(loadedData.count, pngData.count, "round-trip byte count mismatch")
        guard let loadedImage = NSImage(data: loadedData),
              let loadedRep = loadedImage.representations.first as? NSBitmapImageRep else {
            XCTFail("Round-tripped PNG could not be re-decoded as NSImage")
            return
        }
        XCTAssertEqual(loadedRep.pixelsWide, 1280)
        XCTAssertEqual(loadedRep.pixelsHigh, 720)

        // Optional snapshot assertion so visual regressions show up in the report.
        // Loose precision because text antialiasing drifts across macOS minor versions.
        let nsImage = NSImage(cgImage: cg, size: NSSize(width: 1280, height: 720))
        assertSnapshot(of: nsImage, as: .image(precision: 0.97))
    }
}
