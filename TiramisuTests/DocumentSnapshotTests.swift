import Testing
import Foundation
@testable import Tiramisu

@Suite("DocumentSnapshot — file format codable round-trip")
struct DocumentSnapshotTests {

    /// Encodes a minimal DocumentSnapshot with one of each layer kind to JSON,
    /// decodes it back, and asserts the layer count + kinds preserved. This
    /// is the .tiramisu file format's smoke test — if it breaks, every saved
    /// document on disk becomes unloadable.
    @Test("DocumentSnapshot survives a JSON round-trip with all 4 layer kinds")
    func roundTripAllLayerKinds() throws {
        let snap = DocumentSnapshot(
            version: 1,
            canvasWidth: 1280,
            canvasHeight: 720,
            background: .white,
            activeLayerID: nil,
            layers: [
                LayerSnapshot(id: UUID(), name: "background",  kind: .raster),
                LayerSnapshot(id: UUID(), name: "headline",    kind: .text),
                LayerSnapshot(id: UUID(), name: "gradient",    kind: .gradient),
                LayerSnapshot(id: UUID(), name: "solid color", kind: .solid),
            ]
        )

        let data = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(DocumentSnapshot.self, from: data)

        #expect(decoded.canvasWidth == 1280)
        #expect(decoded.canvasHeight == 720)
        #expect(decoded.layers.count == 4)
        #expect(decoded.layers[0].kind == .raster)
        #expect(decoded.layers[1].kind == .text)
        #expect(decoded.layers[2].kind == .gradient)
        #expect(decoded.layers[3].kind == .solid)
    }

    /// Verifies that loading an older / minimal snapshot (only the required
    /// fields) succeeds and applies sensible defaults for missing keys. This
    /// is the forward-compatibility check — old project files saved before we
    /// added new layer-style fields must still load without crashing.
    @Test("Loading a minimal layer snapshot fills in defaults for missing keys")
    func toleratesOldFileFormat() throws {
        // Hand-crafted JSON that's missing many of the optional fields.
        let json = """
        {
          "version": 1,
          "canvasWidth": 1280,
          "canvasHeight": 720,
          "background": { "r": 1, "g": 1, "b": 1, "a": 1 },
          "layers": [
            { "id": "11111111-1111-1111-1111-111111111111", "name": "old layer", "kind": "raster" }
          ]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(DocumentSnapshot.self, from: json)
        #expect(decoded.layers.count == 1)
        let layer = decoded.layers[0]
        #expect(layer.name == "old layer")
        #expect(layer.kind == .raster)
        #expect(layer.visible == true, "missing 'visible' should default to true")
        #expect(layer.opacity == 1.0, "missing 'opacity' should default to 1.0")
        #expect(layer.blend == .normal, "missing 'blend' should default to .normal")
        #expect(layer.styles.dropShadow.enabled == false, "missing 'styles' should default to all-disabled")
    }

    /// Round-trip preserves a non-default opacity, blend, and styles
    /// configuration. Catches subtle Codable bugs where a field decodes but
    /// loses its value (e.g. wrong CodingKey, default override).
    @Test("Non-default layer fields survive round-trip")
    func preservesNonDefaultFields() throws {
        var layer = LayerSnapshot(id: UUID(), name: "configured", kind: .text)
        layer.opacity = 0.6
        layer.blend = .multiply
        layer.styles.dropShadow.enabled = true
        layer.styles.dropShadow.opacity = 0.42

        let snap = DocumentSnapshot(
            version: 1, canvasWidth: 100, canvasHeight: 100,
            background: .black, activeLayerID: nil, layers: [layer]
        )

        let data = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(DocumentSnapshot.self, from: data)
        let restored = decoded.layers[0]

        #expect(restored.opacity == 0.6)
        #expect(restored.blend == .multiply)
        #expect(restored.styles.dropShadow.enabled == true)
        #expect(abs(restored.styles.dropShadow.opacity - 0.42) < 0.001)
    }
}
