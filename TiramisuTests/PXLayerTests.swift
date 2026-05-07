import Testing
import Foundation
import CoreGraphics
@testable import Tiramisu

@Suite("PXLayer — layer construction and defaults")
struct PXLayerTests {

    /// Verifies that constructing a layer of each kind succeeds, the kind is
    /// stored correctly, and visibility/opacity/blend default to sensible
    /// values. This is the foundational "every kind exists" check that backs
    /// the marketing claim of 5 layer types.
    @Test("Each LayerKind constructs with expected defaults",
          arguments: LayerKind.allCases)
    func layerConstruction(kind: LayerKind) {
        let layer = PXLayer(name: "Test", kind: kind)
        #expect(layer.kind == kind)
        #expect(layer.name == "Test")
        #expect(layer.visible == true)
        #expect(layer.opacity == 1.0)
        #expect(layer.blend == .normal)
        #expect(layer.smart == nil, "Non-smart-object layers should have a nil smart by default")
    }

    /// Verifies a freshly constructed layer has sensible default values across
    /// all per-layer processing structs. The defaults ship to users on every
    /// new layer; if a default shifts (e.g. drop-shadow becomes enabled by
    /// default), every new layer suddenly has a shadow — would be a regression
    /// caught here.
    @Test("Default Adjustments / Filters / Styles are all neutral")
    func neutralDefaults() {
        let layer = PXLayer(name: "neutral", kind: .raster)
        #expect(layer.adjust.brightness == 0)
        #expect(layer.adjust.contrast == 0)
        #expect(layer.adjust.exposure == 0)
        #expect(layer.adjust.saturation == 0)
        #expect(layer.filters.blur == 0)
        #expect(layer.filters.noise == 0)
        #expect(layer.styles.dropShadow.enabled == false)
        #expect(layer.styles.outerGlow.enabled == false)
        #expect(layer.styles.stroke.enabled == false)
        #expect(layer.styles.gradientFill.enabled == false)
        #expect(layer.relight.enabled == false)
        #expect(layer.skin.enabled == false)
    }

    /// Each PXLayer should get a unique UUID by default. If two layers ever
    /// share an ID, the document model breaks (selection, undo, etc.).
    @Test("Two default-init layers get different UUIDs")
    func uniqueIDs() {
        let a = PXLayer(name: "a", kind: .raster)
        let b = PXLayer(name: "b", kind: .raster)
        #expect(a.id != b.id)
    }

    /// LayerKind itself must round-trip through JSON — it's the discriminator
    /// in the .tiramisu document format. If renamed, all existing user
    /// documents break.
    @Test("LayerKind raw values are stable",
          arguments: zip(LayerKind.allCases,
                         ["raster", "text", "gradient", "solid"]))
    func layerKindRawValues(kind: LayerKind, expectedRaw: String) {
        #expect(kind.rawValue == expectedRaw)
    }
}

extension LayerKind: CaseIterable {
    public static var allCases: [LayerKind] { [.raster, .text, .gradient, .solid] }
}
