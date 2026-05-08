import Testing
import Foundation
@testable import Tiramisu

/// Sanity checks for the curated preset library powering the Adjust >
/// Lighting > preset chip row. We don't pin the exact slider values
/// (those are tuneable), just that the structure is sane and named
/// presets exist with non-trivial deltas.
@Suite("AdjustPreset library")
struct AdjustPresetTests {

    @Test("Library has the curated set of named presets")
    func library() {
        let names = AdjustPreset.library.map(\.id)
        #expect(names.contains("original"))
        #expect(names.contains("punchy"))
        #expect(names.contains("cinematic"))
        #expect(names.contains("pastel"))
        #expect(names.contains("faded"))
        #expect(names.contains("warm"))
        #expect(names.contains("cool"))
        #expect(names.contains("bw"))
    }

    @Test("Preset IDs are unique")
    func uniqueIDs() {
        let ids = AdjustPreset.library.map(\.id)
        #expect(Set(ids).count == ids.count, "Duplicate preset id detected")
    }

    @Test("Original preset is the zero-Adjustments identity")
    func originalIsZero() {
        let original = AdjustPreset.library.first { $0.id == "original" }!
        #expect(original.target == Adjustments())
    }

    @Test("Non-original presets have at least one non-zero channel")
    func presetsAreNonTrivial() {
        for preset in AdjustPreset.library where preset.id != "original" {
            let a = preset.target
            let isAllZero = a.brightness == 0 && a.contrast == 0 && a.exposure == 0
                && a.saturation == 0 && a.warmth == 0 && a.shadows == 0 && a.highlights == 0
            #expect(!isAllZero, "Preset '\(preset.id)' is all-zero — would be a no-op")
        }
    }

    @Test("Channel values stay within model ranges")
    func presetsStayInRange() {
        for preset in AdjustPreset.library {
            let a = preset.target
            #expect((-1...1).contains(a.brightness), "\(preset.id) brightness out of range")
            #expect((-1...1).contains(a.contrast),   "\(preset.id) contrast out of range")
            #expect((-2...2).contains(a.exposure),   "\(preset.id) exposure out of range")
            #expect((-1...1).contains(a.saturation), "\(preset.id) saturation out of range")
            #expect((-1...1).contains(a.warmth),     "\(preset.id) warmth out of range")
            #expect((-1...1).contains(a.shadows),    "\(preset.id) shadows out of range")
            #expect((-1...1).contains(a.highlights), "\(preset.id) highlights out of range")
        }
    }

    @Test("B&W preset fully desaturates")
    func bwDesaturates() {
        let bw = AdjustPreset.library.first { $0.id == "bw" }!
        #expect(bw.target.saturation == -1.0)
    }

    @Test("Warm preset is warmer than Cool preset")
    func warmVsCool() {
        let warm = AdjustPreset.library.first { $0.id == "warm" }!
        let cool = AdjustPreset.library.first { $0.id == "cool" }!
        #expect(warm.target.warmth > cool.target.warmth)
    }

    @Test("Auto-Enhance is non-trivial and stays in range")
    func autoEnhance() {
        let a = AdjustPreset.auto
        let isAllZero = a.brightness == 0 && a.contrast == 0 && a.exposure == 0
            && a.saturation == 0 && a.warmth == 0 && a.shadows == 0 && a.highlights == 0
        #expect(!isAllZero)
        #expect((-1...1).contains(a.contrast))
        #expect((-1...1).contains(a.saturation))
    }
}
