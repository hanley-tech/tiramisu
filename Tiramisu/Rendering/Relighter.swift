import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins

enum Relighter {
    /// Parametric relight: ambient is an EV shift; the key light is a radial
    /// gradient that fades from (tint, alpha=intensity) at the center to
    /// (clear, alpha=0) at the radius, composited via Screen blend. This means
    /// intensity truly dials the effect to zero, and the tint color shows up
    /// exactly as you pick it (white = just brightens, warm = warm highlight).
    static func apply(_ image: CIImage, settings: Relight, extent: CGRect) -> CIImage {
        guard settings.enabled else { return image }
        var out = image

        // 1. Ambient → EV shift on the whole layer.
        if settings.ambient != 0 {
            let exposure = CIFilter.exposureAdjust()
            exposure.inputImage = out
            exposure.ev = Float(settings.ambient)
            out = exposure.outputImage?.cropped(to: extent) ?? out
        }

        // 2. Key light — gradient with alpha fading from `intensity` to 0, Screen-blended.
        let intensity = max(0, min(2, settings.intensity))
        if intensity > 0.001 {
            let cx = settings.position.x * extent.width
            let cy = (1 - settings.position.y) * extent.height
            let radius = max(1, settings.radius * max(extent.width, extent.height))

            let centerAlpha = min(1, intensity)
            let hot = CIColor(red: settings.color.r,
                              green: settings.color.g,
                              blue: settings.color.b,
                              alpha: centerAlpha)
            let clear = CIColor(red: 0, green: 0, blue: 0, alpha: 0)

            let key = CIFilter.radialGradient()
            key.center = CGPoint(x: cx, y: cy)
            key.radius0 = 0
            key.radius1 = Float(radius)
            key.color0 = hot
            key.color1 = clear
            guard let rawOverlay = key.outputImage?.cropped(to: extent) else { return out }

            // Mask the gradient to the subject's alpha BEFORE blending. This way
            // the light never touches pixels outside the cutout, so feathered
            // edges don't get brightened by the screen blend. Source-in multiplies
            // the overlay by the source's alpha channel.
            let maskedOverlay = rawOverlay.applyingFilter("CISourceInCompositing", parameters: [
                kCIInputBackgroundImageKey: image
            ]).cropped(to: extent)

            // Screen respects the masked overlay's alpha for a clean localized highlight.
            let passes = intensity > 1 ? 2 : 1
            for _ in 0..<passes {
                out = maskedOverlay.applyingFilter("CIScreenBlendMode", parameters: [
                    kCIInputBackgroundImageKey: out
                ]).cropped(to: extent)
            }
        }

        return out
    }
}
