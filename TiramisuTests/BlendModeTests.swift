import Testing
import Foundation
@testable import Tiramisu

@Suite("BlendMode — Photoshop-class blend modes")
struct BlendModeTests {

    /// Verifies all 16 Photoshop-class blend modes are present in the BlendMode
    /// enum's allCases collection. If anyone accidentally removes a case (or
    /// adds one without updating the marketing copy), this catches it.
    @Test("Has 16 blend modes — full Photoshop parity")
    func sixteenBlendModes() {
        let count = BlendMode.allCases.count
        #expect(count == 16, "Expected 16 blend modes, got \(count). The 'AI-NATIVE' marketing pillar mentions 16; if you've added or removed one, update the roadmap and pillar copy.")
    }

    /// Verifies the canonical blend modes have stable rawValues. These string
    /// keys land in .tiramisu document files; if we ever rename one, every
    /// existing user document breaks. This is a tripwire against accidental
    /// renames.
    @Test("Canonical raw values are stable")
    func rawValuesAreStable() {
        #expect(BlendMode.normal.rawValue == "normal")
        #expect(BlendMode.multiply.rawValue == "multiply")
        #expect(BlendMode.screen.rawValue == "screen")
        #expect(BlendMode.overlay.rawValue == "overlay")
        #expect(BlendMode.softLight.rawValue == "soft-light")
        #expect(BlendMode.hardLight.rawValue == "hard-light")
        #expect(BlendMode.colorDodge.rawValue == "color-dodge")
        #expect(BlendMode.colorBurn.rawValue == "color-burn")
        #expect(BlendMode.lighten.rawValue == "lighten")
        #expect(BlendMode.darken.rawValue == "darken")
        #expect(BlendMode.difference.rawValue == "difference")
        #expect(BlendMode.exclusion.rawValue == "exclusion")
        #expect(BlendMode.hue.rawValue == "hue")
        #expect(BlendMode.saturation.rawValue == "saturation")
        #expect(BlendMode.color.rawValue == "color")
        #expect(BlendMode.luminosity.rawValue == "luminosity")
    }

    /// Encodes and decodes every BlendMode through JSON, asserts equality.
    /// Catches any drift between the enum's raw-value-encoded form and the
    /// document format's expectations.
    @Test("Every blend mode round-trips through JSON")
    func everyModeCodableRoundTrip() throws {
        for mode in BlendMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(BlendMode.self, from: data)
            #expect(decoded == mode)
        }
    }
}
