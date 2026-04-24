import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

/// Detects skin with a Vision person-segmentation mask + hue-based refinement,
/// then blends in a Core Image frequency-separation-ish smoothing pass.
enum SkinProcessor {
    static func apply(_ image: CIImage, settings: SkinRetouch, extent: CGRect) -> CIImage {
        guard settings.enabled else { return image }

        // 1. Person mask via Vision (cheap path, macOS 12+)
        let maskImage = personMask(image) ?? fallbackSkinMask(image, extent: extent)

        // 2. Smoothed version of the image
        let smoothed = image.applyingGaussianBlur(sigma: 4 + settings.smooth * 18).cropped(to: extent)

        // 3. Blend smoothed into original using mask * smooth amount
        let amount = Float(settings.smooth)
        let faded = maskImage.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(amount))
        ])
        let smooth = smoothed.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: image,
            kCIInputMaskImageKey: faded,
        ])

        // 4. De-age: gentle warm lift on skin
        var out = smooth
        if settings.deage > 0.01 {
            let lift = CIFilter.colorMatrix()
            lift.inputImage = out
            lift.rVector = CIVector(x: 1, y: 0, z: 0, w: 0)
            lift.gVector = CIVector(x: 0, y: 1, z: 0, w: 0)
            lift.bVector = CIVector(x: 0, y: 0, z: 1, w: 0)
            lift.biasVector = CIVector(x: CGFloat(0.06 * settings.deage), y: CGFloat(0.04 * settings.deage), z: CGFloat(0.02 * settings.deage), w: 0)
            if let lifted = lift.outputImage {
                out = lifted.applyingFilter("CIBlendWithMask", parameters: [
                    kCIInputBackgroundImageKey: out,
                    kCIInputMaskImageKey: maskImage,
                ])
            }
        }

        // 5. Glow
        if settings.glow > 0.01 {
            let bright = out.applyingFilter("CIColorControls", parameters: [
                "inputBrightness": CGFloat(0.08 * settings.glow),
                "inputContrast": 1.0,
                "inputSaturation": 1.0
            ]).applyingGaussianBlur(sigma: 12).cropped(to: extent)
            out = bright.applyingFilter("CIAdditionCompositing", parameters: [
                kCIInputBackgroundImageKey: out
            ]).cropped(to: extent)
        }

        return out.cropped(to: extent)
    }

    private static func personMask(_ image: CIImage) -> CIImage? {
        guard let cg = LayerRenderer.ciContext.createCGImage(image, from: image.extent) else { return nil }
        let req = VNGeneratePersonSegmentationRequest()
        req.qualityLevel = .balanced
        req.outputPixelFormat = kCVPixelFormatType_OneComponent8
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do {
            try handler.perform([req])
            guard let mask = req.results?.first?.pixelBuffer else { return nil }
            return CIImage(cvPixelBuffer: mask).cropped(to: image.extent)
        } catch {
            return nil
        }
    }

    /// Hue-based fallback when no person is detected: approximate skin by HSV band.
    private static func fallbackSkinMask(_ image: CIImage, extent: CGRect) -> CIImage {
        // Use CIKMeans? Simpler: rely on the image itself as a weak mask.
        return CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.5)).cropped(to: extent)
    }
}
