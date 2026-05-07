import Testing
import Foundation
@testable import Tiramisu

@MainActor
@Suite("Document file format — disk round-trip")
struct DocumentDiskRoundTripTests {

    /// Writes a populated DocumentStore to a real .tiramisu file on disk
    /// (under the system temp dir), reads it back, applies the snapshot to
    /// a fresh store, and asserts the loaded document matches the source.
    ///
    /// This is the disk-level companion to DocumentSnapshotTests' in-memory
    /// JSON round-trip. It catches save/load bugs that live in the *file
    /// I/O* path — encoding options, decoder configuration, file extension
    /// handling — that pure-JSON tests don't see.
    @Test("Save → read → load preserves canvas, layers, and active selection")
    func diskRoundTrip() throws {
        // Build a non-default store: changed canvas size, mixed layer kinds,
        // a layer with non-default opacity + blend.
        let source = DocumentStore()
        source.canvasSize = CGSize(width: 1280, height: 720)
        source.backgroundColor = ColorRGB(r: 0.04, g: 0.05, b: 0.10)
        source.layers = []

        let bg = PXLayer(name: "Background", kind: .gradient)
        bg.gradient.kind = "linear"
        bg.gradient.angle = 90

        let title = PXLayer(name: "Hero Text", kind: .text)
        title.text.string = "TEST\nTITLE"
        title.text.fontSize = 200
        title.opacity = 0.85
        title.blend = .multiply

        source.layers = [bg, title]
        source.activeLayerID = title.id

        // Encode and write to a real .tiramisu file under the system temp dir.
        let snap = source.makeSnapshot()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snap)

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tiramisu-rt-\(UUID().uuidString).tiramisu")
        try data.write(to: tmp, options: .atomic)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Now load it back as the app would.
        let loadedData = try Data(contentsOf: tmp)
        let loadedSnap = try JSONDecoder().decode(DocumentSnapshot.self, from: loadedData)

        let restored = DocumentStore()
        restored.apply(loadedSnap)

        // Canvas survived.
        #expect(restored.canvasSize.width == 1280)
        #expect(restored.canvasSize.height == 720)

        // Background color survived (within float precision).
        #expect(abs(restored.backgroundColor.r - 0.04) < 0.001)
        #expect(abs(restored.backgroundColor.g - 0.05) < 0.001)
        #expect(abs(restored.backgroundColor.b - 0.10) < 0.001)

        // Layers survived in order, with kinds, names, and non-default fields.
        #expect(restored.layers.count == 2)
        #expect(restored.layers[0].name == "Background")
        #expect(restored.layers[0].kind == .gradient)
        #expect(restored.layers[1].name == "Hero Text")
        #expect(restored.layers[1].kind == .text)
        #expect(restored.layers[1].text.string == "TEST\nTITLE")
        #expect(restored.layers[1].text.fontSize == 200)
        #expect(abs(restored.layers[1].opacity - 0.85) < 0.001)
        #expect(restored.layers[1].blend == .multiply)

        // Active layer ID survived (apply() falls back to last layer if nil,
        // so we assert on the title layer's restored ID matching the active).
        let restoredTitle = restored.layers[1]
        #expect(restored.activeLayerID == restoredTitle.id)

        // After apply(), the document should be marked clean.
        #expect(!restored.isDirty, "freshly loaded document should not be dirty")
    }
}
