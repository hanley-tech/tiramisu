import XCTest
import SnapshotTesting
import CoreGraphics
import AppKit
@testable import Tiramisu

/// Showcase compositions — full thumbnails / posts / covers built end-to-end
/// through the real renderer. Each golden PNG doubles as:
///
///   1. A regression test (fail if any feature regresses)
///   2. A demonstration of what Tiramisu can produce
///   3. A reusable asset for README, marketing site, social posts
///
/// Goldens live in `TiramisuTests/__Snapshots__/ShowcaseThumbnailTests/`
/// and are committed. Looser precision threshold (0.95) because text
/// antialiasing + CIFilter blur drift slightly across macOS minor versions.
@MainActor
final class ShowcaseThumbnailTests: XCTestCase {

    // MARK: - YouTube thumbnail (1280×720)

    /// Travel-vlog style YT thumbnail: real photo subject (CC-licensed
    /// Unsplash photo from the Fixtures bundle) on the right side as a
    /// smart object, punchy gradient bg, big bold headline with stroke +
    /// glow on the left. The kind of layout creators ship daily for
    /// "VLOGGED MY DAY IN ___" videos.
    func testYouTubeReactionThumbnail() throws {
        let store = DocumentStore()
        store.canvasSize = CGSize(width: 1280, height: 720)
        store.backgroundColor = ColorRGB(r: 0.04, g: 0.05, b: 0.10)
        store.layers = []

        // Background: deep purple → magenta diagonal
        let bg = PXLayer(name: "BG Gradient", kind: .gradient)
        bg.gradient.kind = "linear"
        bg.gradient.angle = 135
        bg.gradient.c1 = ColorRGB(r: 0.20, g: 0.08, b: 0.45)
        bg.gradient.c2 = ColorRGB(r: 0.92, g: 0.18, b: 0.42)
        store.layers.append(bg)

        // Vignette
        let vignette = PXLayer(name: "Vignette", kind: .gradient)
        vignette.gradient.kind = "linear"
        vignette.gradient.angle = 90
        vignette.gradient.c1 = ColorRGB(r: 1, g: 1, b: 1)
        vignette.gradient.c2 = ColorRGB(r: 0.05, g: 0.02, b: 0.10)
        vignette.blend = .multiply
        vignette.opacity = 0.45
        store.layers.append(vignette)

        // Real photo subject — loaded from the bundled CC-licensed fixture.
        let cafePhoto = try fixture(named: "cafe", ext: "jpg")
        guard let subject = store.placeSmartImage(data: cafePhoto, format: "jpg") else {
            return XCTFail("placeSmartImage failed for fixture photo")
        }
        // Position on the right side. placeSmartImage centers and fits;
        // we shift right + scale up slightly so it dominates the right third.
        subject.smart?.centerX = 1280 - 320
        subject.smart?.centerY = 360
        subject.styles.dropShadow.enabled = true
        subject.styles.dropShadow.color = .black
        subject.styles.dropShadow.opacity = 0.55
        subject.styles.dropShadow.distance = 14
        subject.styles.dropShadow.blur = 24

        // Headline — centered on the left third of the canvas.
        let headline = PXLayer(name: "Headline", kind: .text)
        headline.text.string = "VLOG\nDAY 47"
        headline.text.fontName = "System"
        headline.text.fontSize = 180
        headline.text.weight = 800
        headline.text.alignment = "center"
        headline.text.lineHeight = 0.95
        headline.text.color = .white
        headline.text.anchorX = 0.27
        headline.text.anchorY = 0.42
        headline.styles.stroke.enabled = true
        headline.styles.stroke.color = .black
        headline.styles.stroke.size = 8
        headline.styles.outerGlow.enabled = true
        headline.styles.outerGlow.color = ColorRGB(r: 1.0, g: 0.85, b: 0.20)
        headline.styles.outerGlow.opacity = 0.85
        headline.styles.outerGlow.size = 60
        headline.styles.dropShadow.enabled = true
        headline.styles.dropShadow.color = .black
        headline.styles.dropShadow.opacity = 0.55
        headline.styles.dropShadow.distance = 14
        headline.styles.dropShadow.blur = 18
        store.layers.append(headline)

        // Subhead — small caps, accent color, centered under headline
        let subhead = PXLayer(name: "Subhead", kind: .text)
        subhead.text.string = "I FOUND THE BEST CAFE"
        subhead.text.fontName = "System"
        subhead.text.fontSize = 32
        subhead.text.weight = 700
        subhead.text.alignment = "center"
        subhead.text.tracking = 4
        subhead.text.color = ColorRGB(r: 1.0, g: 0.92, b: 0.40)
        subhead.text.anchorX = 0.27
        subhead.text.anchorY = 0.78
        subhead.styles.stroke.enabled = true
        subhead.styles.stroke.color = .black
        subhead.styles.stroke.size = 3
        store.layers.append(subhead)

        let cg = LayerRenderer.composite(store: store)!
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        assertSnapshot(of: img, as: .image(precision: 0.95))
    }

    /// Loads a CC-licensed photo from the bundled `Fixtures/` directory.
    /// See `TiramisuTests/Fixtures/ATTRIBUTION.md` for sources and license.
    private func fixture(named name: String, ext: String) throws -> Data {
        let bundle = Bundle(for: ShowcaseThumbnailTests.self)
        guard let url = bundle.url(forResource: name, withExtension: ext) else {
            throw NSError(domain: "ShowcaseThumbnailTests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Fixture \(name).\(ext) is not in the test bundle. Check project.yml's TiramisuTests resources block."
            ])
        }
        return try Data(contentsOf: url)
    }

    // MARK: - Instagram square post (1080×1080)

    /// Pastel quote post: soft gradient, centered serif, subtle shadow.
    /// The aesthetic IG creators use for quote / mood / launch posts.
    func testInstagramQuotePost() throws {
        let store = DocumentStore()
        store.canvasSize = CGSize(width: 1080, height: 1080)
        store.backgroundColor = ColorRGB(r: 0.97, g: 0.92, b: 0.86)
        store.layers = []

        // Soft pastel gradient — peach → cream
        let bg = PXLayer(name: "BG Gradient", kind: .gradient)
        bg.gradient.kind = "linear"
        bg.gradient.angle = 160
        bg.gradient.c1 = ColorRGB(r: 0.99, g: 0.85, b: 0.78)
        bg.gradient.c2 = ColorRGB(r: 0.99, g: 0.95, b: 0.85)
        store.layers.append(bg)

        // Quote
        let quote = PXLayer(name: "Quote", kind: .text)
        quote.text.string = "the only way\nout\nis through"
        quote.text.fontName = "System Serif"
        quote.text.fontSize = 110
        quote.text.weight = 400
        quote.text.italic = true
        quote.text.alignment = "center"
        quote.text.lineHeight = 1.35
        quote.text.color = ColorRGB(r: 0.36, g: 0.20, b: 0.14)
        quote.text.anchorX = 0.5
        quote.text.anchorY = 0.50
        quote.styles.dropShadow.enabled = true
        quote.styles.dropShadow.color = .black
        quote.styles.dropShadow.opacity = 0.10
        quote.styles.dropShadow.distance = 4
        quote.styles.dropShadow.blur = 8
        store.layers.append(quote)

        // Subtle attribution line
        let attribution = PXLayer(name: "Attribution", kind: .text)
        attribution.text.string = "— A. JOURNAL ENTRY"
        attribution.text.fontName = "System"
        attribution.text.fontSize = 28
        attribution.text.weight = 600
        attribution.text.alignment = "center"
        attribution.text.tracking = 4
        attribution.text.color = ColorRGB(r: 0.55, g: 0.36, b: 0.26)
        attribution.text.anchorX = 0.5
        attribution.text.anchorY = 0.85
        store.layers.append(attribution)

        let cg = LayerRenderer.composite(store: store)!
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        assertSnapshot(of: img, as: .image(precision: 0.95))
    }

    // MARK: - Podcast cover (1500×1500)

    /// Two-tone podcast cover: cocoa top, parchment bottom, episode badge,
    /// massive serif title spanning both halves. Spotify-card friendly.
    /// Uses a near-hard-stop gradient (s1≈0.49, s2≈0.51) to fake the split
    /// since the renderer's gradient is two-stop.
    func testPodcastCover() throws {
        let cocoa = ColorRGB(r: 0.29, g: 0.17, b: 0.10)
        let parchment = ColorRGB(r: 0.98, g: 0.94, b: 0.86)

        let store = DocumentStore()
        store.canvasSize = CGSize(width: 1500, height: 1500)
        store.backgroundColor = parchment
        store.layers = []

        // Hard split: cocoa top, parchment bottom, narrow blend zone in the middle.
        // Renderer's angle convention puts c1 at the END of the gradient axis
        // for angle=90, so to land cocoa on top we put it as c2 and parchment
        // as c1, with a near-instantaneous transition right at the midpoint.
        let split = PXLayer(name: "Split Tone", kind: .gradient)
        split.gradient.kind = "linear"
        split.gradient.angle = 90
        split.gradient.c1 = parchment
        split.gradient.s1 = 0.495
        split.gradient.c2 = cocoa
        split.gradient.s2 = 0.505
        store.layers.append(split)

        // Episode badge on the cocoa half (parchment-tinted)
        let episode = PXLayer(name: "Episode", kind: .text)
        episode.text.string = "EPISODE 042"
        episode.text.fontName = "System Mono"
        episode.text.fontSize = 44
        episode.text.weight = 700
        episode.text.tracking = 10
        episode.text.color = ColorRGB(r: 0.98, g: 0.88, b: 0.70)
        episode.text.anchorX = 0.5
        episode.text.anchorY = 0.20
        store.layers.append(episode)

        // Subtitle on the cocoa half — small caps style
        let subtitle = PXLayer(name: "Subtitle", kind: .text)
        subtitle.text.string = "THE PODCAST ABOUT SHIPPING"
        subtitle.text.fontName = "System"
        subtitle.text.fontSize = 36
        subtitle.text.weight = 600
        subtitle.text.tracking = 7
        subtitle.text.color = ColorRGB(r: 0.96, g: 0.78, b: 0.58)
        subtitle.text.anchorX = 0.5
        subtitle.text.anchorY = 0.36
        store.layers.append(subtitle)

        // Big serif title in cocoa, sitting on the parchment half
        let title = PXLayer(name: "Title", kind: .text)
        title.text.string = "Tiramisu"
        title.text.fontName = "System Serif"
        title.text.fontSize = 280
        title.text.weight = 700
        title.text.italic = true
        title.text.color = cocoa
        title.text.anchorX = 0.5
        title.text.anchorY = 0.66
        store.layers.append(title)

        // Tagline at the bottom of the parchment half
        let tagline = PXLayer(name: "Tagline", kind: .text)
        tagline.text.string = "ship something. tell us about it."
        tagline.text.fontName = "System Serif"
        tagline.text.fontSize = 42
        tagline.text.italic = true
        tagline.text.color = ColorRGB(r: 0.55, g: 0.36, b: 0.26)
        tagline.text.anchorX = 0.5
        tagline.text.anchorY = 0.85
        store.layers.append(tagline)

        let cg = LayerRenderer.composite(store: store)!
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        assertSnapshot(of: img, as: .image(precision: 0.95))
    }

    // MARK: - Tech product hero (1920×1080)

    /// Minimalist tech product launch banner: dark gradient, big title,
    /// small uppercase strapline. The kind of hero a SaaS startup ships.
    func testProductLaunchHero() throws {
        let store = DocumentStore()
        store.canvasSize = CGSize(width: 1920, height: 1080)
        store.backgroundColor = ColorRGB(r: 0.04, g: 0.05, b: 0.10)
        store.layers = []

        // Deep navy → soft indigo gradient
        let bg = PXLayer(name: "BG", kind: .gradient)
        bg.gradient.kind = "linear"
        bg.gradient.angle = 135
        bg.gradient.c1 = ColorRGB(r: 0.04, g: 0.05, b: 0.12)
        bg.gradient.c2 = ColorRGB(r: 0.10, g: 0.20, b: 0.45)
        store.layers.append(bg)

        // Subtle radial-ish bright-spot via a screen-blended low-opacity gradient
        let glow = PXLayer(name: "Center Glow", kind: .gradient)
        glow.gradient.kind = "linear"
        glow.gradient.angle = 90
        glow.gradient.c1 = ColorRGB(r: 0.40, g: 0.65, b: 1.0)
        glow.gradient.c2 = ColorRGB(r: 0.04, g: 0.05, b: 0.12)
        glow.gradient.s1 = 0.30
        glow.gradient.s2 = 1.0
        glow.blend = .screen
        glow.opacity = 0.35
        store.layers.append(glow)

        // Eyebrow line above the title
        let eyebrow = PXLayer(name: "Eyebrow", kind: .text)
        eyebrow.text.string = "INTRODUCING"
        eyebrow.text.fontName = "System"
        eyebrow.text.fontSize = 32
        eyebrow.text.weight = 600
        eyebrow.text.tracking = 10
        eyebrow.text.color = ColorRGB(r: 0.55, g: 0.78, b: 1.0)
        eyebrow.text.anchorX = 0.5
        eyebrow.text.anchorY = 0.36
        store.layers.append(eyebrow)

        // Hero title
        let title = PXLayer(name: "Hero", kind: .text)
        title.text.string = "Tiramisu"
        title.text.fontName = "System"
        title.text.fontSize = 240
        title.text.weight = 800
        title.text.color = .white
        title.text.anchorX = 0.5
        title.text.anchorY = 0.50
        title.styles.dropShadow.enabled = true
        title.styles.dropShadow.color = ColorRGB(r: 0.10, g: 0.20, b: 0.45)
        title.styles.dropShadow.opacity = 0.6
        title.styles.dropShadow.distance = 10
        title.styles.dropShadow.blur = 32
        store.layers.append(title)

        // Strapline + version badge
        let strapline = PXLayer(name: "Strapline", kind: .text)
        strapline.text.string = "FREE · OPEN SOURCE · MADE FOR CREATORS"
        strapline.text.fontName = "System"
        strapline.text.fontSize = 26
        strapline.text.weight = 500
        strapline.text.tracking = 6
        strapline.text.color = ColorRGB(r: 0.75, g: 0.85, b: 1.0)
        strapline.text.anchorX = 0.5
        strapline.text.anchorY = 0.66
        store.layers.append(strapline)

        let cg = LayerRenderer.composite(store: store)!
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        assertSnapshot(of: img, as: .image(precision: 0.95))
    }
}
