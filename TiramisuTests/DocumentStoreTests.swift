import Testing
import Foundation
@testable import Tiramisu

@MainActor
@Suite("DocumentStore — central editing state, undo/redo, layer ops")
struct DocumentStoreTests {

    /// Adding a layer should append it, set it active, and push an undo
    /// snapshot onto the stack so Cmd-Z can remove it.
    @Test("addLayer appends, sets active, and is undoable")
    func addLayerSetsActiveAndIsUndoable() {
        let store = DocumentStore()
        store.layers = []
        let layer = PXLayer(name: "fresh", kind: .raster)

        store.addLayer(layer)

        #expect(store.layers.count == 1)
        #expect(store.activeLayerID == layer.id)
        #expect(store.canUndo, "addLayer must push an undo checkpoint")
        #expect(!store.canRedo)

        store.performUndo()
        #expect(store.layers.isEmpty, "undo should remove the just-added layer")
        #expect(store.canRedo, "undo must populate the redo stack")
    }

    /// Undo + redo are symmetric: undoing an op then redoing it should leave
    /// the store identical to immediately after the op.
    @Test("undo then redo restores the post-op state")
    func undoRedoRoundTrip() {
        let store = DocumentStore()
        store.layers = []
        let a = PXLayer(name: "A", kind: .raster)
        store.addLayer(a)
        let b = PXLayer(name: "B", kind: .text)
        store.addLayer(b)

        #expect(store.layers.map(\.name) == ["A", "B"])

        store.performUndo()                         // remove B
        #expect(store.layers.map(\.name) == ["A"])

        store.performRedo()                         // re-add B
        #expect(store.layers.map(\.name) == ["A", "B"])
        #expect(store.activeLayerID == b.id, "redo should restore active layer too")
    }

    /// Removing the active layer should drop it and pick a new active layer
    /// (last in the stack) so the inspector never points to a missing ID.
    @Test("removeActive drops the layer and reassigns activeLayerID")
    func removeActiveReassignsActive() {
        let store = DocumentStore()
        store.layers = []
        let a = PXLayer(name: "A", kind: .raster)
        let b = PXLayer(name: "B", kind: .text)
        store.addLayer(a)
        store.addLayer(b)
        #expect(store.activeLayerID == b.id)

        store.removeActive()                        // drops B (active)
        #expect(store.layers.map(\.name) == ["A"])
        #expect(store.activeLayerID == a.id, "active should fall back to remaining layer")

        store.performUndo()                         // bring B back
        #expect(store.layers.count == 2)
    }

    /// Reordering via moveToFront / moveForward changes the layers array
    /// and creates an undo checkpoint. "Front" means top of the layer stack
    /// (last in the array, drawn last, on top visually).
    @Test("moveToFront brings the layer to the top of the stack")
    func reorderToFront() {
        let store = DocumentStore()
        store.layers = []
        let a = PXLayer(name: "A", kind: .raster)
        let b = PXLayer(name: "B", kind: .text)
        let c = PXLayer(name: "C", kind: .gradient)
        store.addLayer(a)
        store.addLayer(b)
        store.addLayer(c)
        #expect(store.layers.map(\.name) == ["A", "B", "C"])

        store.moveToFront(a.id)
        #expect(store.layers.map(\.name) == ["B", "C", "A"],
                "A should be last (top of stack)")

        store.performUndo()
        #expect(store.layers.map(\.name) == ["A", "B", "C"],
                "undo should restore original order")
    }

    /// Duplicate clones the active layer, gives it a new UUID, and renames
    /// it with a " copy" suffix so the user can see it's a copy in the panel.
    @Test("duplicateActive clones with a new UUID and a 'copy' suffix")
    func duplicateActive() {
        let store = DocumentStore()
        store.layers = []
        let original = PXLayer(name: "Hero", kind: .text)
        original.opacity = 0.7
        store.addLayer(original)

        store.duplicateActive()

        #expect(store.layers.count == 2)
        let copy = store.layers.last!
        #expect(copy.id != original.id, "duplicate must have a fresh UUID")
        #expect(copy.name == "Hero copy")
        #expect(copy.opacity == 0.7, "duplicate should preserve non-default fields")
    }
}
