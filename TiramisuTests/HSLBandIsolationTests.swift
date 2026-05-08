import XCTest
import CoreImage
import CoreGraphics
import AppKit
@testable import Tiramisu

/// Algorithmic verification of the HSL pipeline. Snapshots prove "the pixels
/// changed in some particular way"; these tests prove "the pixels changed
/// *correctly* — band isolation, monotonicity, and identity round-trip".
///
/// Catches three classes of regression that snapshot diffing misses:
///   1. Band leakage (a redSat slider that secretly desaturates orange too)
///   2. Non-monotonic effects (slider at 0.5 not landing between 0 and 1)
///   3. Identity drift (the LUT path producing slightly-shifted output even
///      when all sliders are at 0)
@MainActor
final class HSLBandIsolationTests: XCTestCase {

    // MARK: - Identity round-trip

    func testIdentityLUTRoundTripsPixels() throws {
        // Force the LUT path with identity HSL, bypassing the renderer's
        // `isIdentity` skip. The cube's cells equal their indices by
        // construction so round-trip should be near-byte-exact (limited
        // only by 32-step LUT quantization + sRGB ↔ working-space rounding).
        let parrots = try fixture(named: "kodim23", ext: "png")
        guard let nsImg = NSImage(data: parrots),
              let cg = nsImg.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return XCTFail("kodim23 didn't decode")
        }
        let ci = CIImage(cgImage: cg)
        let out = LayerRenderer.applyHSL(ci, hsl: HSLAdjustments())
        guard let outCG = LayerRenderer.ciContext.createCGImage(out, from: ci.extent) else {
            return XCTFail("identity LUT output didn't materialize")
        }

        let before = HSLBandMetrics.metrics(of: cg)
        let after  = HSLBandMetrics.metrics(of: outCG)
        for band in HSLBandMetrics.HueBand.allCases {
            guard let b = before[band], let a = after[band] else { continue }
            XCTAssertEqual(a.meanSat, b.meanSat, accuracy: 0.02,
                           "Identity LUT should not move \(band.label) saturation")
            XCTAssertEqual(a.meanLum, b.meanLum, accuracy: 0.02,
                           "Identity LUT should not move \(band.label) luminance")
            // Hue can drift slightly across grid cells; allow ±2°.
            let dHue = abs(HSLBandMetrics.circularHueDelta(b.meanHue, a.meanHue))
            XCTAssertLessThan(dHue, 2.0,
                              "Identity LUT should not move \(band.label) hue (drifted \(dHue)°)")
        }
    }

    // MARK: - Band isolation

    func testRedSatCutsRedAndPreservesOthers() throws {
        let baseline = try renderMetrics(hsl: HSLAdjustments())
        var hsl = HSLAdjustments(); hsl.redSat = -1
        let after = try renderMetrics(hsl: hsl)

        guard let bRed = baseline[.red], let aRed = after[.red] else {
            return XCTFail("Need red pixels in fixture")
        }
        XCTAssertLessThan(aRed.meanSat, bRed.meanSat * 0.6,
                          "redSat=-1 should cut red band sat ≥40% (got \(bRed.meanSat) → \(aRed.meanSat))")

        // Bands that don't share an edge with red (i.e., not orange/magenta —
        // those are adjacent and leak by design through the smooth band
        // weighting). Yellow / green / aqua / blue should all be untouched.
        for band in [HSLBandMetrics.HueBand.yellow, .green, .aqua, .blue] {
            guard let b = baseline[band], let a = after[band] else { continue }
            let tolerance = max(0.05, b.meanSat * 0.10)
            XCTAssertEqual(a.meanSat, b.meanSat, accuracy: tolerance,
                           "redSat=-1 should not affect \(band.label) sat (got \(b.meanSat) → \(a.meanSat))")
        }
    }

    func testAquaLumCutsAquaAndPreservesOthers() throws {
        // kodim23's "blue" macaw is actually aqua/turquoise (hue ~180°), not
        // pure blue (240°). Targets the band where the fixture has real
        // saturated content; tests of blue-band on kodim23 would barely move
        // anything because few pixels classify there.
        let baseline = try renderMetrics(hsl: HSLAdjustments())
        var hsl = HSLAdjustments(); hsl.aquaLum = -0.7
        let after = try renderMetrics(hsl: hsl)

        guard let bAqua = baseline[.aqua], let aAqua = after[.aqua] else {
            return XCTFail("Need aqua pixels in fixture")
        }
        XCTAssertLessThan(aAqua.meanLum, bAqua.meanLum * 0.85,
                          "aquaLum=-0.7 should drop aqua band lum (got \(bAqua.meanLum) → \(aAqua.meanLum))")

        // Non-adjacent bands — red / orange / yellow — should not shift
        // their luminance from an aqua-only move. (green and blue are
        // adjacent and leak by design through the smooth band weighting.)
        for band in [HSLBandMetrics.HueBand.red, .orange, .yellow] {
            guard let b = baseline[band], let a = after[band] else { continue }
            let tolerance = max(0.04, b.meanLum * 0.08)
            XCTAssertEqual(a.meanLum, b.meanLum, accuracy: tolerance,
                           "aquaLum=-0.7 should not affect \(band.label) lum (got \(b.meanLum) → \(a.meanLum))")
        }
    }

    func testGreenHueShiftsGreenTowardYellow() throws {
        // At large hue rotations, mean-hue per band misleads — pixels cross
        // band boundaries and get reclassified, so the remaining band's mean
        // can drift in the wrong direction. The robust signal is migration:
        // green-band pixel count drops, yellow-band count rises.
        let baseline = try renderMetrics(hsl: HSLAdjustments())
        var hsl = HSLAdjustments(); hsl.greenHue = 1.0
        let after = try renderMetrics(hsl: hsl)

        guard let bGreen = baseline[.green], let aGreen = after[.green],
              let bYellow = baseline[.yellow], let aYellow = after[.yellow] else {
            return XCTFail("Need green + yellow pixels in fixture")
        }
        // Lightroom convention: positive green Hue rotates toward yellow.
        // Migration: green band loses pixels, yellow band gains.
        XCTAssertLessThan(aGreen.pixelCount, Int(Double(bGreen.pixelCount) * 0.85),
            "greenHue=+1 should shrink the green band's pixel count by ≥15% (got \(bGreen.pixelCount) → \(aGreen.pixelCount))")
        XCTAssertGreaterThan(aYellow.pixelCount, Int(Double(bYellow.pixelCount) * 1.10),
            "greenHue=+1 should grow the yellow band's pixel count by ≥10% (got \(bYellow.pixelCount) → \(aYellow.pixelCount))")

        // Non-adjacent bands' pixel counts shouldn't shift much.
        for band in [HSLBandMetrics.HueBand.red, .blue, .magenta] {
            guard let b = baseline[band], let a = after[band] else { continue }
            let ratio = Double(a.pixelCount) / Double(max(1, b.pixelCount))
            XCTAssertEqual(ratio, 1.0, accuracy: 0.10,
                "greenHue=+1 should not migrate \(band.label) pixels (ratio \(ratio))")
        }
    }

    // MARK: - Monotonicity

    func testRedSatIsMonotonicAcrossSliderRange() throws {
        let stops = [-1.0, -0.5, 0.0, 0.5, 1.0]
        var redSatPath = [Double]()
        for v in stops {
            var hsl = HSLAdjustments(); hsl.redSat = v
            let m = try renderMetrics(hsl: hsl)
            guard let red = m[.red] else { return XCTFail("Need red pixels") }
            redSatPath.append(red.meanSat)
        }
        // Strictly non-decreasing as the slider moves up. Allow tiny epsilon
        // for already-saturated pixels hitting the 1.0 ceiling at +1.
        for i in 1..<redSatPath.count {
            XCTAssertGreaterThanOrEqual(redSatPath[i] + 0.005, redSatPath[i - 1],
                "redSat path should be monotonic non-decreasing: \(redSatPath)")
        }
        // And the extremes should differ meaningfully.
        let spread = redSatPath.last! - redSatPath.first!
        XCTAssertGreaterThan(spread, 0.10,
            "redSat=-1 vs +1 should produce >10% spread in red-band saturation (got \(spread))")
    }

    // MARK: - Helpers

    private func renderMetrics(hsl: HSLAdjustments)
        throws -> [HSLBandMetrics.HueBand: HSLBandMetrics.BandStats] {
        let store = DocumentStore()
        store.canvasSize = CGSize(width: 960, height: 640)
        store.backgroundColor = ColorRGB(r: 0.10, g: 0.10, b: 0.12)
        store.layers = []
        let parrots = try fixture(named: "kodim23", ext: "png")
        guard let photo = store.placeSmartImage(data: parrots, format: "png") else {
            throw NSError(domain: "HSLBandIsolationTests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "placeSmartImage failed for kodim23"
            ])
        }
        var adj = Adjustments(); adj.hsl = hsl
        photo.adjust = adj
        store.invalidate()
        guard let cg = LayerRenderer.composite(store: store) else {
            throw NSError(domain: "HSLBandIsolationTests", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "composite returned nil"
            ])
        }
        return HSLBandMetrics.metrics(of: cg)
    }

    private func fixture(named name: String, ext: String) throws -> Data {
        let bundle = Bundle(for: HSLBandIsolationTests.self)
        guard let url = bundle.url(forResource: name, withExtension: ext) else {
            throw NSError(domain: "HSLBandIsolationTests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Fixture \(name).\(ext) is not in the test bundle."
            ])
        }
        return try Data(contentsOf: url)
    }
}
