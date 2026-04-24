import Foundation
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

enum BGRemovalError: Error { case noMask, cannotRender }

/// Uses Vision's built-in `VNGenerateForegroundInstanceMaskRequest` (macOS 14+) —
/// no model download, runs on Neural Engine.
enum BackgroundRemover {
    static func remove(_ image: CGImage) async throws -> CGImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        guard let observation = request.results?.first else { throw BGRemovalError.noMask }
        let maskedPixelBuffer = try observation.generateMaskedImage(
            ofInstances: observation.allInstances,
            from: handler,
            croppedToInstancesExtent: false
        )
        let ci = CIImage(cvPixelBuffer: maskedPixelBuffer)
        guard let cg = LayerRenderer.ciContext.createCGImage(ci, from: ci.extent) else {
            throw BGRemovalError.cannotRender
        }
        return cg
    }
}
