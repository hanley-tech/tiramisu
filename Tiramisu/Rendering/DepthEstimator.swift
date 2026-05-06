import Foundation
import CoreML
import Vision
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

enum DepthError: LocalizedError {
    case modelNotBundled
    case inferenceFailed
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .modelNotBundled:
            return "Depth model not found. Run `scripts/download-depth-model.sh` to fetch DepthAnythingV2 (~25 MB)."
        case .inferenceFailed: return "Depth inference failed."
        case .renderFailed:    return "Could not render depth image."
        }
    }
}

enum DepthEstimator {
    static var modelName: String { "DepthAnythingV2SmallF16" }

    static var isModelAvailable: Bool {
        Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") != nil ||
        Bundle.main.url(forResource: modelName, withExtension: "mlpackage") != nil
    }

    /// Runs monocular depth on a CGImage. Returns a grayscale depth map the
    /// same extent as the input (depth near=white / far=black, or vice versa
    /// depending on the shipped model — we normalize downstream).
    static func estimateDepth(_ image: CGImage) async throws -> CGImage {
        guard let url =
            Bundle.main.url(forResource: modelName, withExtension: "mlmodelc")
            ?? Bundle.main.url(forResource: modelName, withExtension: "mlpackage")
        else {
            throw DepthError.modelNotBundled
        }

        let config = MLModelConfiguration()
        config.computeUnits = .all
        let coreML = try MLModel(contentsOf: url, configuration: config)
        let vnModel = try VNCoreMLModel(for: coreML)

        let req = VNCoreMLRequest(model: vnModel)
        req.imageCropAndScaleOption = .scaleFill

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([req])

        guard let obs = req.results?.first as? VNPixelBufferObservation else {
            throw DepthError.inferenceFailed
        }

        let ci = CIImage(cvPixelBuffer: obs.pixelBuffer)
        // Resize back to source dimensions so downstream kernels line up.
        let scaleX = CGFloat(image.width) / ci.extent.width
        let scaleY = CGFloat(image.height) / ci.extent.height
        let resized = ci.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        let extent = CGRect(x: 0, y: 0, width: image.width, height: image.height)

        // Normalize to 0…1 using min/max. The network's output range varies.
        let norm = normalize01(resized).cropped(to: extent)
        guard let cg = LayerRenderer.ciContext.createCGImage(norm, from: extent) else {
            throw DepthError.renderFailed
        }
        return cg
    }

    /// Stretches values to [0, 1] using CIAreaMinMaxRed + color matrix.
    private static func normalize01(_ image: CIImage) -> CIImage {
        let extentVec = CIVector(x: image.extent.origin.x, y: image.extent.origin.y,
                                 z: image.extent.width, w: image.extent.height)
        // CIAreaMinimum and CIAreaMaximum give 1x1 RGBA images with the min/max.
        let minF = CIFilter(name: "CIAreaMinimum",
                            parameters: [kCIInputImageKey: image,
                                         kCIInputExtentKey: extentVec])!
        let maxF = CIFilter(name: "CIAreaMaximum",
                            parameters: [kCIInputImageKey: image,
                                         kCIInputExtentKey: extentVec])!
        guard let minImg = minF.outputImage, let maxImg = maxF.outputImage else { return image }
        // Read pixels.
        let minPx = read1x1(minImg)
        let maxPx = read1x1(maxImg)
        let lo = min(minPx.r, min(minPx.g, minPx.b))
        let hi = max(maxPx.r, max(maxPx.g, maxPx.b))
        let range = max(0.0001, hi - lo)
        let scale = CGFloat(1.0 / range)
        let bias = CGFloat(-lo / range)
        let f = CIFilter.colorMatrix()
        f.inputImage = image
        f.rVector = CIVector(x: scale, y: 0, z: 0, w: 0)
        f.gVector = CIVector(x: 0, y: scale, z: 0, w: 0)
        f.bVector = CIVector(x: 0, y: 0, z: scale, w: 0)
        f.biasVector = CIVector(x: bias, y: bias, z: bias, w: 0)
        return f.outputImage ?? image
    }

    private static func read1x1(_ img: CIImage) -> (r: Double, g: Double, b: Double) {
        var buf = [UInt8](repeating: 0, count: 4)
        LayerRenderer.ciContext.render(img,
                                        toBitmap: &buf,
                                        rowBytes: 4,
                                        bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                        format: .RGBA8,
                                        colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        return (Double(buf[0]) / 255.0,
                Double(buf[1]) / 255.0,
                Double(buf[2]) / 255.0)
    }
}
