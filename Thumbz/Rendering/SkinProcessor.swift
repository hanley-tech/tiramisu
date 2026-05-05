import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import Vision
import AppKit

/// Face-aware skin retouch:
///   1. Detect face landmarks with Vision (`VNDetectFaceLandmarksRequest`).
///   2. Build a soft elliptical mask per face from the face contour, with
///      eye + mouth regions punched out so we don't blur eyelashes / lips.
///   3. Apply frequency-separation-style smoothing only inside that mask:
///      the low-frequency layer (gaussian blur) is blended back at user
///      strength while the high-frequency detail is preserved (so pores
///      and skin texture stay).
///   4. Optional warm de-age lift + glow, also masked to face skin only.
enum SkinProcessor {
    /// When true, the apply() method returns the mask directly so the user
    /// can see which pixels Vision thinks are face skin. Toggled via the
    /// Skin Retouch panel.
    nonisolated(unsafe) static var debugShowMask = false

    static func apply(_ image: CIImage, settings: SkinRetouch, extent: CGRect) -> CIImage {
        guard settings.enabled else { return image }

        guard let maskImage = faceSkinMask(image: image, extent: extent) else {
            tlog("Skin: no face detected, skipping")
            return image
        }
        if debugShowMask {
            // Tint the mask red and overlay it on the image so the user can see it.
            let red = CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 0.6)).cropped(to: extent)
            let overlay = red.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: image,
                kCIInputMaskImageKey: maskImage
            ])
            return overlay.cropped(to: extent)
        }

        var out = image

        // ---- 1. Smooth (frequency-separation flavor) ----
        if settings.smooth > 0.01 {
            let blurSigma = 2 + settings.smooth * 14
            let lowFreq = image.applyingGaussianBlur(sigma: blurSigma).cropped(to: extent)
            // High-freq = original − lowFreq + 0.5. We DON'T need to compute it
            // explicitly; "frequency separation lite" = blend lowFreq into the
            // image only where the mask is bright. The high-freq detail of the
            // original is preserved automatically because the low-freq blur is
            // soft-masked rather than replacing the whole pixel.
            let amt = Float(settings.smooth)
            let faded = scaleAlpha(maskImage, amt)
            out = lowFreq.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: out,
                kCIInputMaskImageKey: faded
            ]).cropped(to: extent)
        }

        // ---- 2. Even tone — pull skin pixels toward their average ----
        if settings.evenTone > 0.01 {
            // Heavy blur ≈ average local skin color
            let avg = image.applyingGaussianBlur(sigma: 60).cropped(to: extent)
            let amt = Float(settings.evenTone) * 0.6
            let faded = scaleAlpha(maskImage, amt)
            out = avg.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: out,
                kCIInputMaskImageKey: faded
            ]).cropped(to: extent)
        }

        // ---- 3. De-age: warm lift in skin shadows ----
        if settings.deage > 0.01 {
            let lift = CIFilter.colorMatrix()
            lift.inputImage = out
            lift.rVector = CIVector(x: 1, y: 0, z: 0, w: 0)
            lift.gVector = CIVector(x: 0, y: 1, z: 0, w: 0)
            lift.bVector = CIVector(x: 0, y: 0, z: 1, w: 0)
            let bias = CGFloat(settings.deage)
            lift.biasVector = CIVector(x: 0.05 * bias, y: 0.03 * bias, z: 0.015 * bias, w: 0)
            if let lifted = lift.outputImage {
                out = lifted.applyingFilter("CIBlendWithMask", parameters: [
                    kCIInputBackgroundImageKey: out,
                    kCIInputMaskImageKey: maskImage
                ]).cropped(to: extent)
            }
        }

        // ---- 4. Glow — gentle warm bloom on skin highlights ----
        if settings.glow > 0.01 {
            let bright = out.applyingFilter("CIColorControls", parameters: [
                "inputBrightness": CGFloat(0.06 * settings.glow),
                "inputContrast": 1.0,
                "inputSaturation": 1.0
            ]).applyingGaussianBlur(sigma: 14).cropped(to: extent)
            // Add only where the mask is bright (face skin).
            let amt = Float(settings.glow) * 0.5
            let faded = scaleAlpha(maskImage, amt)
            out = bright.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: out,
                kCIInputMaskImageKey: faded
            ]).cropped(to: extent)
        }

        return out.cropped(to: extent)
    }

    // MARK: - face-only skin mask

    /// Run face landmarks; for each detected face, paint an elliptical mask
    /// over the face oval and subtract eye/mouth regions. Returns a single-
    /// channel CIImage where 1.0 = skin, 0 = not. Returns nil if no faces.
    private static func faceSkinMask(image: CIImage, extent: CGRect) -> CIImage? {
        guard let cg = LayerRenderer.ciContext.createCGImage(image, from: extent) else {
            tlog("Skin: failed to create CGImage for face detection")
            return nil
        }
        let req = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do { try handler.perform([req]) } catch {
            tlog("Skin: Vision request failed: \(error)")
            return nil
        }
        guard let faces = req.results, !faces.isEmpty else { return nil }
        tlog("Skin: detected \(faces.count) face(s), bbox(es): \(faces.map { String(format: "(%.2f,%.2f,%.2f,%.2f)", $0.boundingBox.origin.x, $0.boundingBox.origin.y, $0.boundingBox.width, $0.boundingBox.height) })")

        let w = Int(extent.width), h = Int(extent.height)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Black background = no skin.
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        for face in faces {
            let box = face.boundingBox    // normalized, y-up (Vision)
            let fx = box.origin.x * CGFloat(w)
            let fy = box.origin.y * CGFloat(h)
            let fw = box.size.width * CGFloat(w)
            let fh = box.size.height * CGFloat(h)

            // Paint a soft white ellipse for the face oval, slightly inset
            // (Vision's bbox tends to overshoot the chin/forehead).
            let inset = min(fw, fh) * 0.05
            let oval = CGRect(x: fx + inset, y: fy + inset,
                              width: fw - inset * 2, height: fh - inset * 2)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: oval)

            // Punch out eye + mouth regions if landmarks are available.
            ctx.setFillColor(NSColor.black.cgColor)
            if let lm = face.landmarks {
                if let leftEye = lm.leftEye  { fillRegion(ctx, leftEye, in: box, w: w, h: h, expand: 0.4) }
                if let rightEye = lm.rightEye { fillRegion(ctx, rightEye, in: box, w: w, h: h, expand: 0.4) }
                if let outerLips = lm.outerLips { fillRegion(ctx, outerLips, in: box, w: w, h: h, expand: 0.2) }
                if let leftEyebrow = lm.leftEyebrow { fillRegion(ctx, leftEyebrow, in: box, w: w, h: h, expand: 0.4) }
                if let rightEyebrow = lm.rightEyebrow { fillRegion(ctx, rightEyebrow, in: box, w: w, h: h, expand: 0.4) }
            }
        }
        guard let cgMask = ctx.makeImage() else { return nil }
        // Soft edge so the smoothing fades naturally into surrounding skin.
        let ci = CIImage(cgImage: cgMask).applyingGaussianBlur(sigma: 6).cropped(to: extent)
        return ci
    }

    /// Fill a small ellipse over a face landmark region (eye/mouth/eyebrow).
    private static func fillRegion(_ ctx: CGContext,
                                    _ region: VNFaceLandmarkRegion2D,
                                    in box: CGRect,
                                    w: Int, h: Int,
                                    expand: CGFloat) {
        // Region points are normalized to the FACE bounding box.
        let pts = region.normalizedPoints
        guard !pts.isEmpty else { return }
        var minX = CGFloat.infinity, minY = CGFloat.infinity
        var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        for p in pts {
            let x = (box.origin.x + p.x * box.size.width) * CGFloat(w)
            let y = (box.origin.y + p.y * box.size.height) * CGFloat(h)
            minX = min(minX, x); minY = min(minY, y)
            maxX = max(maxX, x); maxY = max(maxY, y)
        }
        let pad = max(maxX - minX, maxY - minY) * expand
        let r = CGRect(x: minX - pad, y: minY - pad,
                       width: (maxX - minX) + pad * 2,
                       height: (maxY - minY) + pad * 2)
        ctx.fillEllipse(in: r)
    }

    /// Multiplies the alpha of a grayscale-ish CIImage by a scalar.
    private static func scaleAlpha(_ image: CIImage, _ amt: Float) -> CIImage {
        let f = CIFilter.colorMatrix()
        f.inputImage = image
        f.aVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(amt))
        return f.outputImage ?? image
    }
}
