import Foundation
import AppKit

/// Parses a tiny inline color-markup language out of a plain text string.
/// Syntax: `[#RRGGBB]colored text[/]`  (RGB or RRGGBB both accepted).
/// Returns the stripped plain-text plus the color spans (in the stripped string's coordinates).
enum TextMarkup {
    struct Span {
        let range: NSRange
        let color: NSColor
    }
    struct Parsed {
        let stripped: String
        let spans: [Span]
    }

    private static let pattern = try! NSRegularExpression(
        pattern: #"\[#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})\](.*?)\[/\]"#,
        options: [.dotMatchesLineSeparators]
    )

    static func parse(_ input: String) -> Parsed {
        let ns = input as NSString
        let matches = pattern.matches(in: input, range: NSRange(location: 0, length: ns.length))
        if matches.isEmpty {
            return Parsed(stripped: input, spans: [])
        }

        var result = ""
        var spans: [Span] = []
        var cursor = 0
        for m in matches {
            // Prefix before this match (no formatting).
            let prefix = ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
            result += prefix
            let hex = ns.substring(with: m.range(at: 1))
            let text = ns.substring(with: m.range(at: 2))
            let color = NSColor.fromHex(hex) ?? .white
            let start = (result as NSString).length
            result += text
            let length = (text as NSString).length
            spans.append(Span(range: NSRange(location: start, length: length), color: color))
            cursor = m.range.location + m.range.length
        }
        if cursor < ns.length {
            result += ns.substring(with: NSRange(location: cursor, length: ns.length - cursor))
        }
        return Parsed(stripped: result, spans: spans)
    }
}

extension NSColor {
    var hexString: String {
        let c = self.usingColorSpace(.sRGB) ?? self
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "%02x%02x%02x", r, g, b)
    }

    static func fromHex(_ hex: String) -> NSColor? {
        var h = hex
        if h.count == 3 {
            h = h.map { "\($0)\($0)" }.joined()
        }
        guard h.count == 6, let n = Int(h, radix: 16) else { return nil }
        let r = CGFloat((n >> 16) & 0xFF) / 255.0
        let g = CGFloat((n >> 8) & 0xFF) / 255.0
        let b = CGFloat(n & 0xFF) / 255.0
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}
