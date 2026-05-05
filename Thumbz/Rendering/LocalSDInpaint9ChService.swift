import Foundation
import CoreGraphics
import CoreML
import AppKit
import ImageIO
import UniformTypeIdentifiers
import StableDiffusion

/// True masked-inpainting via SD-1.5 *Inpainting* (9-channel UNet).
///
/// Apple's `ml-stable-diffusion` `StableDiffusionPipeline` can't drive this
/// variant — its scheduler asserts on the input shape mismatch (4 vs 9
/// channels). So we go around it: load each `.mlmodelc` bundle ourselves and
/// run the diffusion loop manually with a direct `MLModel.prediction(from:)`
/// call on the 9-channel UNet. Mask-aware generation eliminates the seam
/// problem the i2i path produces.
/// Loaded SD-1.5 9-ch resources, kept in a reference type so the same instance
/// can be reused across multiple `fill()` calls (Coordinator runs once per
/// tile in Expand mode — 3-6 calls per pass — so reloading the 1.7 GB UNet
/// each time would be 2-3 minutes of wasted load alone).
@MainActor
final class LocalSDInpaint9ChResources {
    let modelDirectory: URL
    let mlConfig: MLModelConfiguration
    let tokenizer: BPETokenizer
    let textEncoder: TextEncoder
    let vaeEncoder: Encoder
    let vaeDecoder: Decoder
    let unet: MLModel

    init(modelDirectory: URL, computeUnits: MLComputeUnits) throws {
        self.modelDirectory = modelDirectory
        let cfg = MLModelConfiguration()
        cfg.computeUnits = computeUnits
        self.mlConfig = cfg
        self.tokenizer = try BPETokenizer(
            mergesAt: modelDirectory.appendingPathComponent("merges.txt"),
            vocabularyAt: modelDirectory.appendingPathComponent("vocab.json"))
        let te = TextEncoder(
            tokenizer: tokenizer,
            modelAt: modelDirectory.appendingPathComponent("TextEncoder.mlmodelc"),
            configuration: cfg)
        try te.loadResources()
        self.textEncoder = te
        let venc = Encoder(
            modelAt: modelDirectory.appendingPathComponent("VAEEncoder.mlmodelc"),
            configuration: cfg)
        try venc.loadResources()
        self.vaeEncoder = venc
        let vdec = Decoder(
            modelAt: modelDirectory.appendingPathComponent("VAEDecoder.mlmodelc"),
            configuration: cfg)
        try vdec.loadResources()
        self.vaeDecoder = vdec
        self.unet = try MLModel(
            contentsOf: modelDirectory.appendingPathComponent("Unet.mlmodelc"),
            configuration: cfg)
    }

    // No deinit cleanup — resources are released when the cache replaces the
    // entry. Adding @MainActor cleanup in deinit collides with deinit's
    // nonisolated context under strict concurrency.
}

/// Process-wide cache of loaded resources keyed by model directory.
@MainActor
private final class LocalSDInpaint9ChResourceCache {
    static let shared = LocalSDInpaint9ChResourceCache()
    private var cached: (key: String, resources: LocalSDInpaint9ChResources)?

    func resources(at directory: URL, computeUnits: MLComputeUnits) throws -> LocalSDInpaint9ChResources {
        let key = directory.path + "|" + String(describing: computeUnits)
        if let c = cached, c.key == key { return c.resources }
        let r = try LocalSDInpaint9ChResources(modelDirectory: directory, computeUnits: computeUnits)
        cached = (key, r)
        return r
    }

    func purge() { cached = nil }
}

struct LocalSDInpaint9ChService: GenerativeFillService {
    let modelDirectory: URL
    let computeUnits: MLComputeUnits
    let stepCount: Int
    let guidanceScale: Float
    let negativePrompt: String

    init(modelDirectory: URL = LocalSDInpaint9ChService.defaultModelDirectory,
         computeUnits: MLComputeUnits = .cpuAndGPU,
         stepCount: Int = 25,
         guidanceScale: Float = 4.0,
         negativePrompt: String = "objects, products, foreground items, light fixtures, equipment, people, text") {
        self.modelDirectory = modelDirectory
        self.computeUnits = computeUnits
        self.stepCount = stepCount
        self.guidanceScale = guidanceScale
        self.negativePrompt = negativePrompt
    }

    var preferredInputSize: CGSize? { CGSize(width: 512, height: 512) }

    static var defaultModelDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Thumbz/Models/sd15-inpaint-9ch", isDirectory: true)
    }

    static var isModelInstalled: Bool {
        let unet = defaultModelDirectory.appendingPathComponent("Unet.mlmodelc/coremldata.bin")
        return FileManager.default.fileExists(atPath: unet.path)
    }

    static var installedVersion: String? {
        let url = defaultModelDirectory.appendingPathComponent("thumbz-version.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["version"] as? String
    }

    static func uninstall() throws {
        try FileManager.default.removeItem(at: defaultModelDirectory)
    }

    static func installedSizeMB() -> Double {
        guard let enumerator = FileManager.default.enumerator(at: defaultModelDirectory,
                                                                includingPropertiesForKeys: [.fileSizeKey])
        else { return 0 }
        var total: Int64 = 0
        for case let f as URL in enumerator {
            if let s = try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize { total += Int64(s) }
        }
        return Double(total) / 1_048_576.0
    }

    func fill(image: CGImage,
              mask: CGImage,
              prompt: String,
              progress: @Sendable @escaping (String) -> Void) async throws -> CGImage {
        // The whole inference must run on MainActor because the loaded ML
        // models (TextEncoder, Encoder, Decoder, MLModel) aren't Sendable and
        // the resource cache is MainActor-isolated.
        try await MainActor.run {
            try fillOnMain(image: image, mask: mask, prompt: prompt, progress: progress)
        }
    }

    @MainActor
    private func fillOnMain(image: CGImage,
                              mask: CGImage,
                              prompt: String,
                              progress: @Sendable @escaping (String) -> Void) throws -> CGImage {
        // Resize input to 512×512 (model's native size).
        let target = CGSize(width: 512, height: 512)
        guard let img512 = LocalSDInpaint9ChService.resize(image, to: target),
              let mask512 = LocalSDInpaint9ChService.resize(mask, to: target) else {
            throw GenerativeFillError.predictionFailed("Could not resize input to 512×512")
        }

        progress("Loading models…")
        // Use process-wide resource cache so we don't reload the 1.7 GB UNet
        // for every tile in a multi-tile Expand pass.
        let res = try LocalSDInpaint9ChResourceCache.shared.resources(at: modelDirectory, computeUnits: computeUnits)

        progress("Encoding prompt…")
        // CFG with NEGATIVE PROMPT: pass `negativePrompt` as the uncond text
        // (instead of empty) to actively suppress object generation in bands.
        let uncondEmbed = try res.textEncoder.encode(negativePrompt)
        let condEmbed = try res.textEncoder.encode(prompt.isEmpty
                                                ? "smooth seamless backdrop continuation, soft gradient, blurry, no objects"
                                                : prompt)        // [1, 77, 768]
        let stackedEmbed = Self.stackBatch(uncondEmbed, condEmbed)  // [2, 77, 768]
        let hiddenStates = Self.toHiddenStates(stackedEmbed)        // [2, 768, 1, 77]

        progress("Encoding image…")
        var rng: RandomSource = SimpleRandomSource()
        // Init latent — VAE-encode the source. Returns [1, 4, 64, 64] (already sampled).
        let initLatent = try res.vaeEncoder.encode(img512, scaleFactor: 0.18215, random: &rng)
        _ = initLatent

        // Masked image: replace mask region (white pixels) with neutral gray.
        // The model uses this as conditioning to know "what's there to preserve".
        guard let maskedImage = Self.applyMask(img512, mask512, fillIntensity: 0.5) else {
            throw GenerativeFillError.predictionFailed("Could not build masked-image input")
        }
        let maskedImageLatent = try res.vaeEncoder.encode(maskedImage, scaleFactor: 0.18215, random: &rng)

        // Latent-resolution mask: 1ch, 64×64, white-where-to-fill.
        let latentMask = try Self.maskAtLatentResolution(mask512)  // [1, 1, 64, 64]

        progress("Sampling noise…")
        // Sample initial noise [1, 4, 64, 64] from the scheduler's initial sigma.
        let noiseDouble = rng.normalShapedArray([1, 4, 64, 64], mean: 0, stdev: 1)
        var noisyLatent = MLShapedArray<Float32>(scalars: noiseDouble.scalars.map { Float32($0) },
                                                 shape: noiseDouble.shape)
        let scheduler = DPMSolverMultistepScheduler(stepCount: stepCount)
        // Scale by initial sigma: scheduler.init_noise_sigma — for DPMSolver this is 1.0
        // (the scheduler.scaleModelInput handles per-step scaling). DPM doesn't need
        // a separate init scale beyond what its own step does.

        progress("Generating…")
        for (i, t) in scheduler.timeSteps.enumerated() {
            // Build 9ch sample: [noisy(4) | mask(1) | masked_image_latent(4)] → [1, 9, 64, 64]
            // Channel order matters — runwayml/stable-diffusion-inpainting was
            // trained with mask before masked_image_latent.
            let nineCh = Self.concatChannels([noisyLatent, latentMask, maskedImageLatent])
            // CFG: batch the same sample twice
            let sampleBatched = Self.stackBatch(nineCh, nineCh)  // [2, 9, 64, 64]
            let timestepArr = MLShapedArray<Float32>(scalars: [Float(t), Float(t)], shape: [2])

            // UNet prediction
            let inputs: [String: Any] = [
                "sample": MLMultiArray(sampleBatched),
                "timestep": MLMultiArray(timestepArr),
                "encoder_hidden_states": MLMultiArray(hiddenStates),
            ]
            let provider = try MLDictionaryFeatureProvider(dictionary: inputs)
            let result = try res.unet.prediction(from: provider)
            guard let noisePredArr = result.featureValue(for: "noise_pred")?.multiArrayValue else {
                throw GenerativeFillError.predictionFailed("UNet returned no noise_pred")
            }
            let noisePred = MLShapedArray<Float32>(noisePredArr)  // [2, 4, 64, 64]
            // CFG: uncond + scale * (cond - uncond)
            let guidedNoise = Self.performGuidance(noisePred, guidanceScale: guidanceScale)
            // Scheduler step
            noisyLatent = scheduler.step(output: guidedNoise, timeStep: t, sample: noisyLatent)

            if i % 5 == 0 || i == scheduler.timeSteps.count - 1 {
                progress("Step \(i + 1) / \(scheduler.timeSteps.count)")
            }
        }

        progress("Decoding…")
        let images = try res.vaeDecoder.decode([noisyLatent], scaleFactor: 0.18215)
        guard let out = images.first else {
            throw GenerativeFillError.predictionFailed("VAE decoder returned no image")
        }
        return out
    }

    // MARK: - Helpers

    static func resize(_ image: CGImage, to size: CGSize) -> CGImage? {
        if image.width == Int(size.width) && image.height == Int(size.height) { return image }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                   bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        return ctx.makeImage()
    }

    /// Replace mask=white pixels in `image` with `fillIntensity` gray. Used to
    /// build the "masked image" that becomes the second VAE-encoded input.
    static func applyMask(_ image: CGImage, _ mask: CGImage, fillIntensity: CGFloat) -> CGImage? {
        let w = image.width, h = image.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h,
                                   bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        // Use the mask's luminance as alpha: where mask is white, draw fill color.
        guard let maskAlpha = grayscaleAlpha(from: mask) else { return ctx.makeImage() }
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: 0, width: w, height: h), mask: maskAlpha)
        ctx.setFillColor(CGColor(srgbRed: fillIntensity, green: fillIntensity, blue: fillIntensity, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.restoreGState()
        return ctx.makeImage()
    }

    /// Convert RGBA mask to a single-channel-grayscale CGImage suitable for
    /// `CGContext.clip(to:mask:)`. The output's pixel intensity drives the clip.
    static func grayscaleAlpha(from mask: CGImage) -> CGImage? {
        let w = mask.width, h = mask.height
        let cs = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                   bitsPerComponent: 8, bytesPerRow: w, space: cs,
                                   bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(mask, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    /// Mask at latent resolution (64×64) as `[1, 1, 64, 64]` Float32.
    /// Resamples the 512×512 mask down by 8× via nearest-neighbor area average.
    static func maskAtLatentResolution(_ mask: CGImage) throws -> MLShapedArray<Float32> {
        // Render mask at 64×64, single channel.
        let cs = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(data: nil, width: 64, height: 64,
                                   bitsPerComponent: 8, bytesPerRow: 64, space: cs,
                                   bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            throw GenerativeFillError.predictionFailed("mask 64x64 ctx alloc failed")
        }
        ctx.interpolationQuality = .high
        ctx.draw(mask, in: CGRect(x: 0, y: 0, width: 64, height: 64))
        guard let cg = ctx.makeImage(),
              let dataProvider = cg.dataProvider,
              let data = dataProvider.data else {
            throw GenerativeFillError.predictionFailed("mask 64x64 read failed")
        }
        let bytes = CFDataGetBytePtr(data)!
        var values = [Float32](repeating: 0, count: 64 * 64)
        for i in 0..<(64 * 64) {
            // PNG/CG y-down vs latent y-up — match what other latents are.
            // Apple's VAE uses standard "first row = top" convention. Match that.
            values[i] = Float32(bytes[i]) / 255.0
        }
        return MLShapedArray<Float32>(scalars: values, shape: [1, 1, 64, 64])
    }

    /// Stack two `[1, ...]` arrays along the first axis → `[2, ...]`.
    static func stackBatch(_ a: MLShapedArray<Float32>, _ b: MLShapedArray<Float32>) -> MLShapedArray<Float32> {
        precondition(a.shape == b.shape, "stackBatch: shape mismatch")
        var newShape = a.shape
        newShape[0] = a.shape[0] + b.shape[0]
        let combined = a.scalars + b.scalars
        return MLShapedArray<Float32>(scalars: combined, shape: newShape)
    }

    /// Concatenate along the channel axis (axis=1) — `[1, c1, h, w] + [1, c2, h, w] → [1, c1+c2, h, w]`.
    static func concatChannels(_ arrays: [MLShapedArray<Float32>]) -> MLShapedArray<Float32> {
        precondition(!arrays.isEmpty, "concatChannels: empty")
        let shape0 = arrays[0].shape
        let h = shape0[2], w = shape0[3]
        let totalC = arrays.reduce(0) { $0 + $1.shape[1] }
        var out = [Float32](repeating: 0, count: 1 * totalC * h * w)
        var cOffset = 0
        for arr in arrays {
            let c = arr.shape[1]
            // Source layout: [1, c, h, w] flat → c * h * w
            // Dest layout:   [1, totalC, h, w] flat → totalC * h * w
            // For each (channel, y, x), write to (cOffset + channel, y, x)
            arr.withUnsafeShapedBufferPointer { ptr, _, _ in
                for ci in 0..<c {
                    for y in 0..<h {
                        for x in 0..<w {
                            let srcIdx = ci * h * w + y * w + x
                            let dstIdx = (cOffset + ci) * h * w + y * w + x
                            out[dstIdx] = ptr[srcIdx]
                        }
                    }
                }
            }
            cOffset += c
        }
        return MLShapedArray<Float32>(scalars: out, shape: [1, totalC, h, w])
    }

    /// Manually transpose [batch, seq, dim] → [batch, dim, 1, seq] to match what
    /// Apple's UNet expects. (Their internal `toHiddenStates` does this; it's
    /// not public so we re-implement.)
    static func toHiddenStates(_ embedding: MLShapedArray<Float32>) -> MLShapedArray<Float32> {
        let from = embedding.shape   // [batch, seq, dim]
        let toShape = [from[0], from[2], 1, from[1]]
        var out = MLShapedArray<Float32>(repeating: 0, shape: toShape)
        for i0 in 0..<from[0] {
            for i1 in 0..<from[1] {
                for i2 in 0..<from[2] {
                    out[scalarAt: i0, i2, 0, i1] = embedding[scalarAt: i0, i1, i2]
                }
            }
        }
        return out
    }

    /// Classifier-Free Guidance: noise[2,...] → guided[1,...] = uncond + scale*(cond - uncond).
    static func performGuidance(_ noise: MLShapedArray<Float32>, guidanceScale: Float) -> MLShapedArray<Float32> {
        var shape = noise.shape
        shape[0] = 1
        let perBatch = noise.scalars.count / 2
        var out = [Float32](repeating: 0, count: perBatch)
        noise.withUnsafeShapedBufferPointer { ptr, _, _ in
            for i in 0..<perBatch {
                let uncond = ptr[i]
                let cond = ptr[i + perBatch]
                out[i] = uncond + guidanceScale * (cond - uncond)
            }
        }
        return MLShapedArray<Float32>(scalars: out, shape: shape)
    }

}

/// Apple's RandomSource concrete impls (NumPyRandomSource / NvRandomSource /
/// TorchRandomSource) are internal to the StableDiffusion package, so we roll
/// our own minimal one — Box-Muller from SystemRandomNumberGenerator. Good
/// enough for inference; not seeded for reproducibility.
struct SimpleRandomSource: RandomSource {
    var rng = SystemRandomNumberGenerator()
    mutating func nextNormal(mean: Double, stdev: Double) -> Double {
        let u1 = max(1e-10, Double.random(in: 0..<1, using: &rng))
        let u2 = Double.random(in: 0..<1, using: &rng)
        let z = (-2.0 * log(u1)).squareRoot() * cos(2 * .pi * u2)
        return mean + z * stdev
    }
    mutating func normalShapedArray(_ shape: [Int], mean: Double, stdev: Double) -> MLShapedArray<Double> {
        let count = shape.reduce(1, *)
        var values = [Double](); values.reserveCapacity(count)
        for _ in 0..<count { values.append(nextNormal(mean: mean, stdev: stdev)) }
        return MLShapedArray<Double>(scalars: values, shape: shape)
    }
}

/// Downloads the pre-converted SD-1.5 inpainting Core ML bundles from the
/// `jc-builds/sd-v1-5-inpainting-coreml` HuggingFace repo into our app
/// support dir. Mirrors `LocalSDInstaller`'s structure; ~2.6 GB on disk.
@MainActor
enum LocalSDInpaint9ChInstaller {
    static let installedModelVersion = "sd-1.5-inpaint-9ch.v1"
    static let baseHFURL = "https://huggingface.co/jc-builds/sd-v1-5-inpainting-coreml/resolve/main"

    static let bundleNames = [
        "TextEncoder.mlmodelc",
        "Unet.mlmodelc",
        "VAEDecoder.mlmodelc",
        "VAEEncoder.mlmodelc",
    ]
    static let auxFiles = ["merges.txt", "vocab.json"]
    static let perBundleFiles = [
        "coremldata.bin", "metadata.json", "model.mil",
        "weights/weight.bin", "analytics/coremldata.bin",
    ]

    static func install(force: Bool = false,
                         progress: @escaping (String, Double) -> Void) async throws {
        let dest = LocalSDInpaint9ChService.defaultModelDirectory
        if !force && LocalSDInpaint9ChService.isModelInstalled
            && LocalSDInpaint9ChService.installedVersion == installedModelVersion {
            progress("Already installed (v\(installedModelVersion))", 1.0)
            return
        }
        if LocalSDInpaint9ChService.isModelInstalled
            && LocalSDInpaint9ChService.installedVersion != installedModelVersion {
            try? FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try await installFromFiles(dest: dest, progress: progress)
        try writeVersion(to: dest)
        progress("Model installed", 1.0)
    }

    private static func installFromFiles(dest: URL,
                                          progress: @escaping (String, Double) -> Void) async throws {
        let total = bundleNames.count * perBundleFiles.count + auxFiles.count
        var done = 0
        for bundle in bundleNames {
            for file in perBundleFiles {
                done += 1
                let frac = Double(done) / Double(total)
                progress("\(bundle) — \(file)", frac)
                let url = URL(string: "\(baseHFURL)/\(bundle)/\(file)")!
                let dst = dest.appendingPathComponent(bundle).appendingPathComponent(file)
                try FileManager.default.createDirectory(at: dst.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                let (tmp, resp) = try await URLSession.shared.download(from: url)
                if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw GenerativeFillError.predictionFailed("HTTP \(http.statusCode) for \(bundle)/\(file)")
                }
                try? FileManager.default.removeItem(at: dst)
                try FileManager.default.moveItem(at: tmp, to: dst)
            }
        }
        for aux in auxFiles {
            done += 1
            let frac = Double(done) / Double(total)
            progress(aux, frac)
            let url = URL(string: "\(baseHFURL)/\(aux)")!
            let dst = dest.appendingPathComponent(aux)
            let (tmp, resp) = try await URLSession.shared.download(from: url)
            if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw GenerativeFillError.predictionFailed("HTTP \(http.statusCode) for \(aux)")
            }
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.moveItem(at: tmp, to: dst)
        }
    }

    private static func writeVersion(to dest: URL) throws {
        let payload: [String: Any] = [
            "version": installedModelVersion,
            "installed": ISO8601DateFormatter().string(from: Date()),
            "source": baseHFURL,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
        try data.write(to: dest.appendingPathComponent("thumbz-version.json"), options: .atomic)
    }
}
