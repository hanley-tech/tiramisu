import XCTest
import SnapshotTesting
import CoreGraphics
import AppKit
@testable import Tiramisu

/// Visual regression for the depth-aware studio relighter. The relight
/// pipeline reads a depth map (Vision), positions a virtual key light
/// in normalized canvas space, and modulates pixel values per-pixel.
/// Tiny changes to the falloff function or depth-bias are visible in
/// every direction the light comes from.
@MainActor
final class RelightSnapshotTests: XCTestCase {

    func testRelightTopLeft() throws {
        try renderRelight(name: "top-left", at: CGPoint(x: 0.20, y: 0.20))
    }

    func testRelightTopRight() throws {
        try renderRelight(name: "top-right", at: CGPoint(x: 0.80, y: 0.20))
    }

    func testRelightCenter() throws {
        try renderRelight(name: "center", at: CGPoint(x: 0.50, y: 0.50))
    }

    func testRelightBottomCenter() throws {
        try renderRelight(name: "bottom-center", at: CGPoint(x: 0.50, y: 0.85))
    }

    func testRelightWarmTint() throws {
        try renderRelight(name: "warm-tint", at: CGPoint(x: 0.30, y: 0.30)) { r in
            r.color = ColorRGB(r: 1.0, g: 0.78, b: 0.55)  // warm tungsten
            r.intensity = 1.1
        }
    }

    func testRelightCoolTint() throws {
        try renderRelight(name: "cool-tint", at: CGPoint(x: 0.70, y: 0.30)) { r in
            r.color = ColorRGB(r: 0.62, g: 0.78, b: 1.0)  // cool blue
            r.intensity = 1.1
        }
    }

    // MARK: - Helpers

    private func renderRelight(name: String, at position: CGPoint, configure: ((inout Relight) -> Void)? = nil) throws {
        let store = DocumentStore()
        store.canvasSize = CGSize(width: 480, height: 320)
        store.backgroundColor = ColorRGB(r: 0.05, g: 0.05, b: 0.07)
        store.layers = []

        let cafe = try fixture(named: "cafe", ext: "jpg")
        guard let photo = store.placeSmartImage(data: cafe, format: "jpg") else {
            return XCTFail("placeSmartImage failed for cafe fixture")
        }
        var relight = photo.relight
        relight.enabled = true
        relight.position = position
        relight.intensity = 0.9
        relight.radius = 0.5
        configure?(&relight)
        photo.relight = relight
        store.invalidate()

        let cg = LayerRenderer.composite(store: store)!
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        // Vision depth + radial-gradient falloff have float-drift across
        // macOS minor versions — looser precision than pure shape rendering.
        assertSnapshot(of: img, as: .image(precision: 0.95), named: name)
    }

    private func fixture(named name: String, ext: String) throws -> Data {
        let bundle = Bundle(for: RelightSnapshotTests.self)
        guard let url = bundle.url(forResource: name, withExtension: ext) else {
            throw NSError(domain: "RelightSnapshotTests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Fixture \(name).\(ext) is not in the test bundle."
            ])
        }
        return try Data(contentsOf: url)
    }
}
