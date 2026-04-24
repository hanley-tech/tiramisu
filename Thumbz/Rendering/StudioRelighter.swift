import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import AppKit

/// AI-depth-based relighting — applied on top of a source + depth map via a
/// Metal-backed CIKernel. Stubbed: the UI wires this in once a depth model
/// is bundled. Until then, `apply()` is a no-op.
enum StudioRelighter {
    static func apply(_ src: CIImage,
                       depth: CIImage?,
                       settings: StudioRelight,
                       extent: CGRect) -> CIImage {
        guard settings.enabled, let depth else { return src }
        // TODO: plug in Metal CIKernel once DepthAnythingV2 model is bundled.
        return src
    }
}
