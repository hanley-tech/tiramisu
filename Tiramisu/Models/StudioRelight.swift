import Foundation
import CoreGraphics

/// AI-depth-based relighting. Depth is computed once (cached) via a Core ML
/// monocular depth model; the shader runs live for every parameter change.
struct StudioRelight: Codable, Sendable, Equatable {
    var enabled: Bool = false
    var hasDepth: Bool = false               // flips true after depth is computed + cached

    // Light direction in *image space*: x/y are UV-like (-1…1), z is toward-camera.
    var lightDirX: Double = 0.35
    var lightDirY: Double = -0.5
    var lightDirZ: Double = 0.7

    var intensity: Double = 1.0              // 0…2 — multiplier on N·L
    var color: ColorRGB = .white             // light tint
    var ambient: Double = 0.35               // 0…1 — fills shadow side
    var softness: Double = 0.25              // 0…1 — soft-wrap (half-Lambert)
    var rimLight: Double = 0.3               // 0…1 — back-light on edges
    var surfaceGain: Double = 10.0           // slope multiplier on depth→normal (tune for subject scale)

    var depthPNG: Data?                      // cached depth map (8-bit grayscale)

    enum CodingKeys: String, CodingKey {
        case enabled, hasDepth
        case lightDirX, lightDirY, lightDirZ
        case intensity, color, ambient, softness, rimLight, surfaceGain
        case depthPNG
    }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        self.hasDepth = try c.decodeIfPresent(Bool.self, forKey: .hasDepth) ?? false
        self.lightDirX = try c.decodeIfPresent(Double.self, forKey: .lightDirX) ?? 0.35
        self.lightDirY = try c.decodeIfPresent(Double.self, forKey: .lightDirY) ?? -0.5
        self.lightDirZ = try c.decodeIfPresent(Double.self, forKey: .lightDirZ) ?? 0.7
        self.intensity = try c.decodeIfPresent(Double.self, forKey: .intensity) ?? 1.0
        self.color = try c.decodeIfPresent(ColorRGB.self, forKey: .color) ?? .white
        self.ambient = try c.decodeIfPresent(Double.self, forKey: .ambient) ?? 0.35
        self.softness = try c.decodeIfPresent(Double.self, forKey: .softness) ?? 0.25
        self.rimLight = try c.decodeIfPresent(Double.self, forKey: .rimLight) ?? 0.3
        self.surfaceGain = try c.decodeIfPresent(Double.self, forKey: .surfaceGain) ?? 10.0
        self.depthPNG = try c.decodeIfPresent(Data.self, forKey: .depthPNG)
    }
}
