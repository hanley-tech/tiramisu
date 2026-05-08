import SwiftUI

/// A named lighting/color preset that resolves to a concrete `Adjustments`
/// configuration. Tapping a preset chip in the Adjust panel writes its
/// `target` directly into `layer.adjust`.
struct AdjustPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let target: Adjustments
    /// Two-color gradient hint shown on the chip — purely visual, gives each
    /// preset a recognizable accent without needing a thumbnail render.
    let accent: (Color, Color)

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: AdjustPreset, rhs: AdjustPreset) -> Bool { lhs.id == rhs.id }
}

extension AdjustPreset {
    /// Curated set of looks. Order is the order they appear in the chip row.
    static let library: [AdjustPreset] = [
        AdjustPreset(
            id: "original", name: "Original",
            target: Adjustments(),
            accent: (Color(white: 0.85), Color(white: 0.65))
        ),
        AdjustPreset(
            id: "punchy", name: "Punchy",
            target: Adjustments(brightness: 0.05, contrast: 0.40, saturation: 0.30, shadows: 0.20),
            accent: (Color(red: 1.0, green: 0.55, blue: 0.20), Color(red: 0.85, green: 0.20, blue: 0.30))
        ),
        AdjustPreset(
            id: "cinematic", name: "Cinematic",
            target: Adjustments(contrast: 0.30, exposure: -0.10, saturation: -0.10, warmth: 0.15, shadows: 0.10, highlights: -0.20),
            accent: (Color(red: 0.20, green: 0.30, blue: 0.45), Color(red: 0.85, green: 0.55, blue: 0.30))
        ),
        AdjustPreset(
            id: "pastel", name: "Pastel",
            target: Adjustments(brightness: 0.10, contrast: -0.20, exposure: 0.20, saturation: -0.20, warmth: 0.10, highlights: 0.10),
            accent: (Color(red: 1.0, green: 0.80, blue: 0.85), Color(red: 0.80, green: 0.85, blue: 1.0))
        ),
        AdjustPreset(
            id: "faded", name: "Faded",
            target: Adjustments(contrast: -0.30, exposure: -0.10, saturation: -0.30, shadows: 0.30),
            accent: (Color(red: 0.75, green: 0.72, blue: 0.68), Color(red: 0.55, green: 0.52, blue: 0.50))
        ),
        AdjustPreset(
            id: "warm", name: "Warm",
            target: Adjustments(exposure: 0.05, saturation: 0.10, warmth: 0.40),
            accent: (Color(red: 1.0, green: 0.78, blue: 0.45), Color(red: 0.90, green: 0.45, blue: 0.20))
        ),
        AdjustPreset(
            id: "cool", name: "Cool",
            target: Adjustments(saturation: 0.05, warmth: -0.40, shadows: 0.10),
            accent: (Color(red: 0.55, green: 0.80, blue: 1.0), Color(red: 0.20, green: 0.40, blue: 0.75))
        ),
        AdjustPreset(
            id: "bw", name: "B&W",
            target: Adjustments(contrast: 0.20, saturation: -1.0),
            accent: (Color(white: 0.95), Color(white: 0.20))
        )
    ]

    /// Heuristic "Auto Enhance" — gentle universal lift. Not as smart as a
    /// histogram-aware enhancement (deferred), but already better than zero.
    static let auto = Adjustments(
        contrast: 0.20,
        saturation: 0.10,
        shadows: 0.15,
        highlights: -0.10
    )
}
