import Foundation
import AppKit
import CoreGraphics
import CoreImage

/// Drives a generative fill operation against a layer and an optional rectangular
/// selection. Produces a new image that's blended into the layer's smart source.
@MainActor
enum GenerativeFillCoordinator {
    /// Run a fill on the active layer's smart source. Replaces pixels inside the
    /// selection rect with the generated content; pixels outside are unchanged.
    /// If `selection` is nil, the fill regenerates the entire image (outpainting/edit).
    static func fill(store: DocumentStore,
                      prompt: String,
                      service: GenerativeFillService) async throws {
        guard let layer = store.activeLayer else {
            throw GenerativeFillError.predictionFailed("No active layer")
        }
        // We require a smart layer — the embedded source is what we feed the model.
        guard let smart = layer.smart, let source = SmartObjectEngine.loadSource(smart) else {
            throw GenerativeFillError.predictionFailed("Active layer must be a Smart Object (drop an image first)")
        }
        let sw = source.width, sh = source.height

        // Build the mask (white = generate here, black = keep original).
        // Selection comes in DOC coords; map to source-image coords using the smart transform.
        let mask = buildMask(sourceSize: CGSize(width: sw, height: sh),
                             selectionDoc: store.selectionRect,
                             smart: smart,
                             canvas: store.canvasSize)

        store.generativeProgress = "Submitting…"
        defer { store.generativeProgress = nil }
        store.checkpoint("Generative Fill")

        let result = try await service.fill(image: source, mask: mask, prompt: prompt) { msg in
            Task { @MainActor in store.generativeProgress = msg }
        }

        // Composite: replace masked region only, keep the rest of the source.
        let merged = composite(original: source, generated: result, mask: mask)
        if let png = LayerSnapshot.encodePNG(merged) {
            layer.smart?.sourceBytes = png
            layer.smart?.sourceFormat = "png"
            layer.smart?.pixelWidth = merged.width
            layer.smart?.pixelHeight = merged.height
            store.invalidate()
            tlog("Generative Fill applied (\(merged.width)x\(merged.height), \(png.count) bytes)")
        } else {
            throw GenerativeFillError.encodeFailed
        }
    }

    /// White rect on black, in source-image pixel coords. If no selection, full white (= regenerate everything).
    private static func buildMask(sourceSize: CGSize,
                                   selectionDoc: CGRect?,
                                   smart: SmartSource,
                                   canvas: CGSize) -> CGImage {
        let w = Int(sourceSize.width), h = Int(sourceSize.height)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: w, height: h,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

        if let docRect = selectionDoc {
            // doc → source-image coords. The smart transform places the source
            // centered at smart.center with smart.scale. So a doc point P maps to
            // source point: (P - center) / scale + sourceSize/2
            let sx = max(0.001, smart.scaleX), sy = max(0.001, smart.scaleY)
            let imgX1 = (docRect.minX - smart.centerX) / sx + sourceSize.width / 2
            let imgY1Top = (docRect.minY - smart.centerY) / sy + sourceSize.height / 2
            let imgX2 = (docRect.maxX - smart.centerX) / sx + sourceSize.width / 2
            let imgY2Top = (docRect.maxY - smart.centerY) / sy + sourceSize.height / 2
            // Source image space here is top-down; CGContext is bottom-up so flip Y.
            let imgY1 = sourceSize.height - imgY2Top
            let imgY2 = sourceSize.height - imgY1Top
            let rect = CGRect(x: imgX1, y: imgY1, width: imgX2 - imgX1, height: imgY2 - imgY1)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fill(CGRect(origin: .zero, size: sourceSize))
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(rect.intersection(CGRect(origin: .zero, size: sourceSize)))
        } else {
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(origin: .zero, size: sourceSize))
        }
        return ctx.makeImage()!
    }

    /// Replace masked pixels in `original` with pixels from `generated`. Other
    /// pixels stay original. Soft-edged (gaussian blur on mask) for natural blend.
    private static func composite(original: CGImage, generated: CGImage, mask: CGImage) -> CGImage {
        let w = original.width, h = original.height
        let extent = CGRect(x: 0, y: 0, width: w, height: h)
        let src = CIImage(cgImage: original)
        // The generated image dimensions may differ; fit to source.
        var gen = CIImage(cgImage: generated)
        if gen.extent != extent {
            let sx = CGFloat(w) / gen.extent.width
            let sy = CGFloat(h) / gen.extent.height
            gen = gen.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        }
        let m = CIImage(cgImage: mask)
            .applyingGaussianBlur(sigma: 6)
            .cropped(to: extent)
        let blended = gen.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: src,
            kCIInputMaskImageKey: m
        ])
        return LayerRenderer.ciContext.createCGImage(blended, from: extent) ?? original
    }
}
