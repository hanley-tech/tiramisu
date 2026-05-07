import Testing
import Foundation
import AppKit
@testable import Tiramisu

@Suite("ColorRGB — color round-trip and codable")
struct ColorRGBTests {

    /// Verifies the basic memberwise initializer stores all four channels and
    /// defaults alpha to 1. The whole rendering pipeline relies on ColorRGB
    /// being a faithful container, so this is the foundational check.
    @Test("Memberwise init stores rgba and defaults alpha to 1")
    func memberwiseInit() {
        let c = ColorRGB(r: 0.25, g: 0.5, b: 0.75)
        #expect(c.r == 0.25)
        #expect(c.g == 0.5)
        #expect(c.b == 0.75)
        #expect(c.a == 1.0)
    }

    /// Verifies the predefined .black and .white sentinels match expected
    /// channel values. These are used extensively in default styles
    /// (DropShadow, Stroke) so divergence here would silently shift defaults.
    @Test("Static .black and .white have expected channels")
    func staticColors() {
        #expect(ColorRGB.black.r == 0)
        #expect(ColorRGB.black.g == 0)
        #expect(ColorRGB.black.b == 0)
        #expect(ColorRGB.white.r == 1)
        #expect(ColorRGB.white.g == 1)
        #expect(ColorRGB.white.b == 1)
    }

    /// Encodes a ColorRGB to JSON, decodes it back, and verifies the round-trip
    /// is bit-equal. Catches regressions in any custom Codable conformance —
    /// e.g. accidentally reordering CodingKeys or dropping the alpha channel.
    @Test("JSON encode/decode round-trip preserves all channels")
    func codableRoundTrip() throws {
        let original = ColorRGB(r: 0.123, g: 0.456, b: 0.789, a: 0.5)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ColorRGB.self, from: data)
        #expect(decoded == original)
    }

    /// Verifies the NSColor convenience initializer correctly samples the sRGB
    /// channels of a color in any color space, and that the result round-trips
    /// to within float-precision tolerance. Document files are loaded as
    /// arbitrary color profiles, so robust sRGB conversion matters.
    @Test("NSColor → ColorRGB normalizes any color space to sRGB")
    func fromNSColor() {
        let ns = NSColor(srgbRed: 0.6, green: 0.3, blue: 0.1, alpha: 1.0)
        let c = ColorRGB(ns)
        #expect(abs(c.r - 0.6) < 0.001)
        #expect(abs(c.g - 0.3) < 0.001)
        #expect(abs(c.b - 0.1) < 0.001)
        #expect(abs(c.a - 1.0) < 0.001)
    }
}
