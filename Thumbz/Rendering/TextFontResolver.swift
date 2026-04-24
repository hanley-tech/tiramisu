import Foundation
import AppKit

/// Builds an NSFont from a TextContent, supporting the SF Pro family variants
/// (Display / Rounded / Mono / Serif) via system font design, plus all weights
/// and italic as a symbolic trait.
enum TextFontResolver {
    static let systemFamilies: [String] = [
        "System",          // SF Pro Text / SF Pro Display (chosen automatically by size)
        "System Rounded",  // SF Pro Rounded
        "System Mono",     // SF Mono
        "System Serif",    // New York
    ]

    static let weights: [(label: String, value: Double, ns: NSFont.Weight)] = [
        ("Ultralight", 100, .ultraLight),
        ("Thin",       200, .thin),
        ("Light",      300, .light),
        ("Regular",    400, .regular),
        ("Medium",     500, .medium),
        ("Semibold",   600, .semibold),
        ("Bold",       700, .bold),
        ("Heavy",      800, .heavy),
        ("Black",      900, .black),
    ]

    static func nsWeight(for value: Double) -> NSFont.Weight {
        weights.min(by: { abs($0.value - value) < abs($1.value - value) })?.ns ?? .regular
    }

    static func font(for t: TextContent) -> NSFont {
        let size = CGFloat(t.fontSize)
        let isSystem = t.fontName.hasPrefix("System") || t.fontName == "System"

        var font: NSFont
        if isSystem {
            let weight = nsWeight(for: t.weight)
            let base = NSFont.systemFont(ofSize: size, weight: weight)
            var descriptor = base.fontDescriptor

            switch t.fontName {
            case "System Rounded":
                descriptor = descriptor.withDesign(.rounded) ?? descriptor
            case "System Mono":
                descriptor = descriptor.withDesign(.monospaced) ?? descriptor
            case "System Serif":
                descriptor = descriptor.withDesign(.serif) ?? descriptor
            default:
                break  // "System" = default design
            }

            if t.italic {
                let symbolic = descriptor.symbolicTraits.union(.italic)
                descriptor = descriptor.withSymbolicTraits(symbolic)
            }

            font = NSFont(descriptor: descriptor, size: size) ?? base
        } else {
            // Named (installed) font family. Try to apply bold/italic as traits.
            let base = NSFont(name: t.fontName, size: size) ?? NSFont.systemFont(ofSize: size, weight: .heavy)
            var descriptor = base.fontDescriptor
            var symbolic = descriptor.symbolicTraits
            if t.weight >= 600 { symbolic.insert(.bold) }
            if t.italic { symbolic.insert(.italic) }
            descriptor = descriptor.withSymbolicTraits(symbolic)
            font = NSFont(descriptor: descriptor, size: size) ?? base
        }

        return font
    }

    /// Installed font families (sorted). Enumerating `availableFontFamilies` is
    /// expensive (100–500 ms on systems with lots of fonts) — cache once.
    static let installedFamilies: [String] = {
        NSFontManager.shared.availableFontFamilies.sorted()
    }()
}
