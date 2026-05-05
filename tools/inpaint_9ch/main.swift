// End-to-end smoke test for the 9-channel SD-1.5 inpainting service.
//
// Loads a test image, builds a synthetic band mask (right N pixels = white =
// "inpaint here"), runs the full 9-channel inference pipeline, and writes
// every intermediate to /tmp/inpaint9ch_test/.
//
// Usage:
//   ThumbzInpaint9ChTest <image> [<bandPx>] [<prompt>]

import Foundation
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import CoreML
import AppKit
import StableDiffusion

// MARK: - args

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: ThumbzInpaint9ChTest <image> [<bandPx>] [<prompt>]\n".utf8))
    exit(2)
}
let imagePath = args[1]
let bandPx: Int = args.count >= 3 ? (Int(args[2]) ?? 192) : 192
let prompt: String = args.count >= 4 ? args[3] : ""

let outDir = URL(fileURLWithPath: "/tmp/inpaint9ch_test")
try? FileManager.default.removeItem(at: outDir)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

print("=== ThumbzInpaint9ChTest ===")
print("Image: \(imagePath)")
print("Band:  right \(bandPx) px (mask white)")
print("Prompt:\(prompt.isEmpty ? "(empty → default)" : " '\(prompt)'")")

func pngWrite(_ image: CGImage, name: String) {
    let url = outDir.appendingPathComponent("\(name).png")
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    print("  wrote \(name).png  (\(image.width)x\(image.height))")
}

// Load + resize source to 512x512.
guard let imgSource = CGImageSourceCreateWithURL(URL(fileURLWithPath: imagePath) as CFURL, nil),
      let raw = CGImageSourceCreateImageAtIndex(imgSource, 0, nil) else {
    FileHandle.standardError.write(Data("Could not load image\n".utf8))
    exit(1)
}
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let imgCtx = CGContext(data: nil, width: 512, height: 512,
                        bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
imgCtx.interpolationQuality = .high
imgCtx.draw(raw, in: CGRect(x: 0, y: 0, width: 512, height: 512))
let img512 = imgCtx.makeImage()!
pngWrite(img512, name: "01-input")

// Build mask: black everywhere, white in a right-side band of `bandPx` pixels.
let maskCtx = CGContext(data: nil, width: 512, height: 512,
                         bitsPerComponent: 8, bytesPerRow: 0, space: space,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
maskCtx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
maskCtx.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
maskCtx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
maskCtx.fill(CGRect(x: 512 - bandPx, y: 0, width: bandPx, height: 512))
let mask512 = maskCtx.makeImage()!
pngWrite(mask512, name: "02-mask")

// Locate the model (try non-sandbox path first since we downloaded there).
let home = FileManager.default.homeDirectoryForCurrentUser
let candidates = [
    home.appendingPathComponent("Library/Application Support/Thumbz/Models/sd15-inpaint-9ch"),
    home.appendingPathComponent("Library/Containers/ai.taiso.Thumbz/Data/Library/Application Support/Thumbz/Models/sd15-inpaint-9ch"),
]
var modelDir: URL?
for c in candidates {
    if FileManager.default.fileExists(atPath: c.appendingPathComponent("Unet.mlmodelc/coremldata.bin").path) {
        modelDir = c; break
    }
}
guard let modelDir else {
    FileHandle.standardError.write(Data("9ch SD model not found in expected locations.\n".utf8))
    exit(3)
}
print("Model: \(modelDir.path)")

// Inline the inference (mirrors LocalSDInpaint9ChService.fill).
let mlConfig = MLModelConfiguration()
mlConfig.computeUnits = .cpuAndGPU
print("Loading models…")
let tokenizer = try BPETokenizer(
    mergesAt: modelDir.appendingPathComponent("merges.txt"),
    vocabularyAt: modelDir.appendingPathComponent("vocab.json"))
let textEncoder = TextEncoder(
    tokenizer: tokenizer,
    modelAt: modelDir.appendingPathComponent("TextEncoder.mlmodelc"),
    configuration: mlConfig)
try textEncoder.loadResources()
let vaeEncoder = Encoder(
    modelAt: modelDir.appendingPathComponent("VAEEncoder.mlmodelc"),
    configuration: mlConfig)
try vaeEncoder.loadResources()
let vaeDecoder = Decoder(
    modelAt: modelDir.appendingPathComponent("VAEDecoder.mlmodelc"),
    configuration: mlConfig)
try vaeDecoder.loadResources()
let unet = try MLModel(contentsOf: modelDir.appendingPathComponent("Unet.mlmodelc"), configuration: mlConfig)

// Tokenize + text encode (cond + NEGATIVE PROMPT for uncond).
print("Encoding prompt…")
let negativePrompt = "phone, smartphone, iphone, device, product, object, item, text, logo, person, plant, furniture, equipment, light, lamp, tripod, stand, studio gear, camera, sharp edges, anything, foreground subject, distinct shapes"
let uncondEmbed = try textEncoder.encode(negativePrompt)
let condEmbed = try textEncoder.encode(prompt.isEmpty
    ? "blurry plain wall, soft white gradient, empty space, photography backdrop, minimal"
    : prompt)
let stacked = stackBatch(uncondEmbed, condEmbed)                     // [2, 77, 768]
let hiddenStates = toHiddenStates(stacked)                           // [2, 768, 1, 77]

// VAE-encode init image.
print("VAE-encoding image…")
var rng: RandomSource = SimpleRandomSource()
let initLatent = try vaeEncoder.encode(img512, scaleFactor: 0.18215, random: &rng)  // [1, 4, 64, 64]
_ = initLatent

// Build masked image and VAE-encode it. Mid-gray (0.5) gives the model
// neutral conditioning so it generates from prompt + negative prompt rather
// than echoing dark space.
let maskedImg = applyMaskToImage(img512, mask512, fillIntensity: 0.5)!
pngWrite(maskedImg, name: "03-masked-input")
let maskedImageLatent = try vaeEncoder.encode(maskedImg, scaleFactor: 0.18215, random: &rng)

// Latent-resolution mask.
let latentMask = try maskAtLatentResolution(mask512)  // [1, 1, 64, 64]

// Diffusion loop.
print("Sampling noise + diffusing…")
let noiseDouble = rng.normalShapedArray([1, 4, 64, 64], mean: 0, stdev: 1)
var noisyLatent = MLShapedArray<Float32>(scalars: noiseDouble.scalars.map { Float32($0) }, shape: noiseDouble.shape)
let scheduler = DPMSolverMultistepScheduler(stepCount: 25)

let totalSteps = scheduler.timeSteps.count
for (i, t) in scheduler.timeSteps.enumerated() {
    // Channel layout MUST be [noisy(4) | mask(1) | masked_image(4)] — that's the
    // order runwayml/stable-diffusion-inpainting was trained with. Wrong order
    // → garbage output.
    let nineCh = concatChannels([noisyLatent, latentMask, maskedImageLatent])
    let sampleBatched = stackBatch(nineCh, nineCh)
    let timestepArr = MLShapedArray<Float32>(scalars: [Float(t), Float(t)], shape: [2])
    let provider = try MLDictionaryFeatureProvider(dictionary: [
        "sample": MLMultiArray(sampleBatched),
        "timestep": MLMultiArray(timestepArr),
        "encoder_hidden_states": MLMultiArray(hiddenStates),
    ])
    let result = try unet.prediction(from: provider)
    guard let nparr = result.featureValue(for: "noise_pred")?.multiArrayValue else {
        FileHandle.standardError.write(Data("UNet returned no noise_pred at step \(i)\n".utf8))
        exit(4)
    }
    let noisePred = MLShapedArray<Float32>(nparr)
    let guided = performGuidance(noisePred, guidanceScale: 7.5)
    noisyLatent = scheduler.step(output: guided, timeStep: t, sample: noisyLatent)
    if i % 5 == 0 || i == totalSteps - 1 {
        print("  step \(i + 1)/\(totalSteps) (t=\(t))")
    }
}

print("VAE-decoding…")
let decoded = try vaeDecoder.decode([noisyLatent], scaleFactor: 0.18215)
guard let outImg = decoded.first else {
    FileHandle.standardError.write(Data("VAE decode returned no images\n".utf8))
    exit(5)
}
pngWrite(outImg, name: "04-result")

print("\nDone. Inspect /tmp/inpaint9ch_test/")

// MARK: - helpers (mirror LocalSDInpaint9ChService.swift; tools target needs its own copies)

func stackBatch(_ a: MLShapedArray<Float32>, _ b: MLShapedArray<Float32>) -> MLShapedArray<Float32> {
    var newShape = a.shape; newShape[0] = a.shape[0] + b.shape[0]
    return MLShapedArray<Float32>(scalars: a.scalars + b.scalars, shape: newShape)
}

func concatChannels(_ arrays: [MLShapedArray<Float32>]) -> MLShapedArray<Float32> {
    let h = arrays[0].shape[2], w = arrays[0].shape[3]
    let totalC = arrays.reduce(0) { $0 + $1.shape[1] }
    var out = [Float32](repeating: 0, count: totalC * h * w)
    var cOffset = 0
    for arr in arrays {
        let c = arr.shape[1]
        arr.withUnsafeShapedBufferPointer { ptr, _, _ in
            for ci in 0..<c {
                for y in 0..<h {
                    for x in 0..<w {
                        out[(cOffset + ci) * h * w + y * w + x] = ptr[ci * h * w + y * w + x]
                    }
                }
            }
        }
        cOffset += c
    }
    return MLShapedArray<Float32>(scalars: out, shape: [1, totalC, h, w])
}

func toHiddenStates(_ embedding: MLShapedArray<Float32>) -> MLShapedArray<Float32> {
    let from = embedding.shape
    let toShape = [from[0], from[2], 1, from[1]]
    var out = MLShapedArray<Float32>(repeating: Float32(0), shape: toShape)
    for i0 in 0..<from[0] {
        for i1 in 0..<from[1] {
            for i2 in 0..<from[2] {
                out[scalarAt: i0, i2, 0, i1] = embedding[scalarAt: i0, i1, i2]
            }
        }
    }
    return out
}

func performGuidance(_ noise: MLShapedArray<Float32>, guidanceScale: Float) -> MLShapedArray<Float32> {
    var shape = noise.shape; shape[0] = 1
    let perBatch = noise.scalars.count / 2
    var out = [Float32](repeating: 0, count: perBatch)
    noise.withUnsafeShapedBufferPointer { ptr, _, _ in
        for i in 0..<perBatch {
            out[i] = ptr[i] + guidanceScale * (ptr[i + perBatch] - ptr[i])
        }
    }
    return MLShapedArray<Float32>(scalars: out, shape: shape)
}

func applyMaskToImage(_ image: CGImage, _ mask: CGImage, fillIntensity: CGFloat) -> CGImage? {
    let w = image.width, h = image.height
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: w, height: h,
                               bitsPerComponent: 8, bytesPerRow: 0, space: space,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let cs = CGColorSpaceCreateDeviceGray()
    guard let mctx = CGContext(data: nil, width: w, height: h,
                                bitsPerComponent: 8, bytesPerRow: w, space: cs,
                                bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return ctx.makeImage() }
    mctx.draw(mask, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let mAlpha = mctx.makeImage() else { return ctx.makeImage() }
    ctx.saveGState()
    ctx.clip(to: CGRect(x: 0, y: 0, width: w, height: h), mask: mAlpha)
    ctx.setFillColor(CGColor(srgbRed: fillIntensity, green: fillIntensity, blue: fillIntensity, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.restoreGState()
    return ctx.makeImage()
}

/// Apple's RandomSource concrete impls (NumPyRandomSource, NvRandomSource,
/// TorchRandomSource) are internal. Roll our own minimal one — Box-Muller
/// from SystemRandomNumberGenerator. Good enough for test/inference.
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

func maskAtLatentResolution(_ mask: CGImage) throws -> MLShapedArray<Float32> {
    let cs = CGColorSpaceCreateDeviceGray()
    guard let ctx = CGContext(data: nil, width: 64, height: 64,
                               bitsPerComponent: 8, bytesPerRow: 64, space: cs,
                               bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
        throw NSError(domain: "mask64", code: 0)
    }
    ctx.interpolationQuality = .high
    ctx.draw(mask, in: CGRect(x: 0, y: 0, width: 64, height: 64))
    guard let cg = ctx.makeImage(),
          let provider = cg.dataProvider,
          let data = provider.data else { throw NSError(domain: "mask64", code: 1) }
    let bytes = CFDataGetBytePtr(data)!
    var values = [Float32](repeating: 0, count: 64 * 64)
    for i in 0..<(64 * 64) { values[i] = Float32(bytes[i]) / 255.0 }
    return MLShapedArray<Float32>(scalars: values, shape: [1, 1, 64, 64])
}
