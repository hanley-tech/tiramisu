// Headless full-pipeline test for the Generative Fill Expand path.
// Loads an image, runs the same prep + tile geometry as the app, then calls
// Apple's StableDiffusion pipeline directly (same model the app uses) on each
// tile. Writes every intermediate to /tmp/expand_full_test/ so we can inspect.
//
// Usage:
//   ThumbzExpandTest <image> <canvasW> <canvasH> [<prompt>] [<strength>]
//
// Looks for the SD-1.5 model bundle at:
//   ~/Library/Application Support/Thumbz/Models/sd15-inpaint/   (non-sandbox)
//   or
//   ~/Library/Containers/ai.taiso.Thumbz/Data/Library/Application Support/Thumbz/Models/sd15-inpaint/
//   (whichever exists)

import Foundation
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import CoreML
import StableDiffusion
import AppKit

// MARK: - args

let args = CommandLine.arguments
guard args.count >= 4,
      let canvasW = Int(args[2]),
      let canvasH = Int(args[3]) else {
    FileHandle.standardError.write(Data("usage: ThumbzExpandTest <image> <W> <H> [<prompt>] [<strength>]\n".utf8))
    exit(2)
}
let imagePath = args[1]
let prompt = args.count >= 5 ? args[4] : "seamless continuation of the existing photo, matching texture, color and lighting, photorealistic"
let strength: Float = (args.count >= 6 ? Float(args[5]) : nil) ?? 0.95
let canvasSize = CGSize(width: canvasW, height: canvasH)

let outDir = URL(fileURLWithPath: "/tmp/expand_full_test")
try? FileManager.default.removeItem(at: outDir)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

print("=== ThumbzExpandTest ===")
print("Image:    \(imagePath)")
print("Canvas:   \(canvasW)x\(canvasH)")
print("Prompt:   \(prompt)")
print("Strength: \(strength)")
print("Out:      \(outDir.path)")

// MARK: - locate model

func resolveModelDir() -> URL? {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let candidates = [
        home.appendingPathComponent("Library/Containers/ai.taiso.Thumbz/Data/Library/Application Support/Thumbz/Models/sd15-inpaint"),
        home.appendingPathComponent("Library/Application Support/Thumbz/Models/sd15-inpaint"),
    ]
    for c in candidates {
        let unet = c.appendingPathComponent("Unet.mlmodelc")
        if FileManager.default.fileExists(atPath: unet.path) { return c }
    }
    return nil
}
guard let modelDir = resolveModelDir() else {
    FileHandle.standardError.write(Data("SD model not found.\n".utf8))
    exit(3)
}
print("Model:    \(modelDir.path)")

// MARK: - load source image

guard let imgSource = CGImageSourceCreateWithURL(URL(fileURLWithPath: imagePath) as CFURL, nil),
      let sourceImage = CGImageSourceCreateImageAtIndex(imgSource, 0, nil) else {
    FileHandle.standardError.write(Data("Could not load image.\n".utf8))
    exit(1)
}
print("Source:   \(sourceImage.width)x\(sourceImage.height)")

// MARK: - helpers

func pngWrite(_ image: CGImage, name: String) {
    let url = outDir.appendingPathComponent("\(name).png")
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    print("  wrote \(name).png  (\(image.width)x\(image.height))")
}

func makeNoise(width: Int, height: Int) -> CGImage {
    let bytesPerRow = width * 4
    var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
    var state = UInt64.random(in: 1..<UInt64.max)
    for i in stride(from: 0, to: bytes.count, by: 4) {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        bytes[i] = UInt8((state &* 6364136223846793005) >> 56)
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        bytes[i+1] = UInt8((state &* 6364136223846793005) >> 56)
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        bytes[i+2] = UInt8((state &* 6364136223846793005) >> 56)
        bytes[i+3] = 255
    }
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    return CGImage(width: width, height: height,
                   bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                   space: space,
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: false,
                   intent: .defaultIntent)!
}

func cropTopDown(_ image: CGImage, to rect: CGRect) -> CGImage? {
    let r = CGRect(x: floor(rect.minX), y: floor(rect.minY),
                   width: floor(rect.width), height: floor(rect.height))
        .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard r.width > 0, r.height > 0 else { return nil }
    return image.cropping(to: r)
}

func resize(_ image: CGImage, to size: CGSize) -> CGImage? {
    if image.width == Int(size.width) && image.height == Int(size.height) { return image }
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                               bitsPerComponent: 8, bytesPerRow: 0, space: space,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(origin: .zero, size: size))
    return ctx.makeImage()
}

/// Multiply an image's alpha by a vertical fade gradient. `fadeTop` and
/// `fadeBottom` flags toggle whether the corresponding edge is feathered;
/// `fadeSize` is in pixels (along the long axis of the band — usually height).
/// Used to cross-fade overlapping tiles within a band.
func applyTileFade(_ image: CGImage,
                    fadeTop: Bool, fadeBottom: Bool,
                    fadeLeft: Bool, fadeRight: Bool,
                    fadeSize: Int) -> CGImage {
    let w = image.width, h = image.height
    let bytesPerRow = w * 4
    var rgba = [UInt8](repeating: 0, count: bytesPerRow * h)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: &rgba, width: w, height: h,
                               bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: space,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        return image
    }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

    let f = max(1, fadeSize)
    func factorAt(x: Int, y: Int) -> Double {
        // CG bytes are top-down here because we drew through the context.
        var fx = 1.0, fy = 1.0
        if fadeTop && y < f {
            fy = min(fy, Double(y) / Double(f))
        }
        if fadeBottom && y >= h - f {
            fy = min(fy, Double(h - 1 - y) / Double(f))
        }
        if fadeLeft && x < f {
            fx = min(fx, Double(x) / Double(f))
        }
        if fadeRight && x >= w - f {
            fx = min(fx, Double(w - 1 - x) / Double(f))
        }
        return fx * fy
    }
    for y in 0..<h {
        for x in 0..<w {
            let i = y * bytesPerRow + x * 4
            let a = Double(rgba[i + 3])
            let f = factorAt(x: x, y: y)
            // Premultiplied: scale RGB and A by the fade factor.
            rgba[i]     = UInt8(Double(rgba[i])     * f)
            rgba[i + 1] = UInt8(Double(rgba[i + 1]) * f)
            rgba[i + 2] = UInt8(Double(rgba[i + 2]) * f)
            rgba[i + 3] = UInt8(a * f)
        }
    }
    return ctx.makeImage() ?? image
}

func clipToMask(_ image: CGImage, mask: CGImage) -> CGImage {
    let extent = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    let src = CIImage(cgImage: image)
    let m = CIImage(cgImage: mask)
        .applyingFilter("CIMaskToAlpha")
        .applyingGaussianBlur(sigma: 6)
        .cropped(to: extent)
    let clear = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: extent)
    let out = src.applyingFilter("CIBlendWithMask", parameters: [
        kCIInputBackgroundImageKey: clear,
        kCIInputMaskImageKey: m,
    ])
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ciCtx = CIContext()
    return ciCtx.createCGImage(out, from: extent, format: .RGBA8, colorSpace: space) ?? image
}

// MARK: - layer placement

let scale = min(canvasSize.width / CGFloat(sourceImage.width),
                canvasSize.height / CGFloat(sourceImage.height))
let lw = CGFloat(sourceImage.width) * scale
let lh = CGFloat(sourceImage.height) * scale
let lx = (canvasSize.width - lw) / 2
let ly = (canvasSize.height - lh) / 2
let layerBounds = CGRect(x: lx, y: ly, width: lw, height: lh)
print("Layer:    bounds=(\(lx),\(ly)) size=(\(lw)x\(lh))  bands L=\(lx) R=\(canvasSize.width - lx - lw) T=\(ly) B=\(canvasSize.height - ly - lh)")

if lx < 1 && ly < 1 && (canvasSize.width - lx - lw) < 1 && (canvasSize.height - ly - lh) < 1 {
    print("\nNothing to expand — source already fills canvas. Exit.")
    exit(0)
}

// MARK: - prep: prepared context (composite + noise bands) + mask

let space = CGColorSpace(name: CGColorSpace.sRGB)!

let composedCtx = CGContext(data: nil, width: canvasW, height: canvasH,
                             bitsPerComponent: 8, bytesPerRow: 0, space: space,
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
composedCtx.interpolationQuality = .high
composedCtx.setFillColor(CGColor(srgbRed: 0.05, green: 0.07, blue: 0.12, alpha: 1))
composedCtx.fill(CGRect(x: 0, y: 0, width: canvasW, height: canvasH))
let drawRect = CGRect(x: layerBounds.minX,
                      y: canvasSize.height - layerBounds.maxY,
                      width: layerBounds.width, height: layerBounds.height)
composedCtx.draw(sourceImage, in: drawRect)
let composed = composedCtx.makeImage()!
pngWrite(composed, name: "01-composed")

// Prepared context: ITERATIVE DIFFUSION FILL.
// Start with: source at layer bounds, transparent everywhere else.
// Each pass: gaussian-blur the whole canvas, then overdraw the sharp source.
// The blur diffuses the layer's edge colors outward into the bands; the
// re-overlay keeps the layer pixel-perfect. After enough passes, the bands
// hold smooth color gradients sourced FROM the layer's edges — no flip, no
// strip, no hard boundary.
let yFlipped = canvasSize.height - layerBounds.maxY
let scaleX2 = layerBounds.width / CGFloat(sourceImage.width)
let scaleY2 = layerBounds.height / CGFloat(sourceImage.height)
_ = (scaleX2, scaleY2)
let canvasOriginRect = CGRect(x: 0, y: 0, width: canvasW, height: canvasH)
let drawSourceRect = CGRect(x: layerBounds.minX, y: yFlipped,
                             width: layerBounds.width, height: layerBounds.height)
let ciCtx = CIContext()

// Pass 0: fill canvas with an OPAQUE neutral gray (so subsequent gaussian
// blurs actually diffuse colors instead of getting alpha-diluted), then draw
// the source on top. This is the correct way to seed iterative diffusion.
let initCtx = CGContext(data: nil, width: canvasW, height: canvasH,
                         bitsPerComponent: 8, bytesPerRow: 0, space: space,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
initCtx.interpolationQuality = .high
initCtx.setFillColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1))
initCtx.fill(canvasOriginRect)
initCtx.draw(sourceImage, in: drawSourceRect)
var current = initCtx.makeImage()!

// Iterate. Each pass: clampedToExtent() so transparent pixels read as edge
// pixels, then gaussian blur to diffuse, then redraw sharp source on top.
let diffusionPasses = 8
let perPassSigma: CGFloat = 50
for _ in 0..<diffusionPasses {
    let blurredCI = CIImage(cgImage: current)
        .clampedToExtent()
        .applyingGaussianBlur(sigma: perPassSigma)
        .cropped(to: canvasOriginRect)
    guard let blurredCG = ciCtx.createCGImage(blurredCI, from: canvasOriginRect,
                                                format: .RGBA8, colorSpace: space)
    else { break }
    let next = CGContext(data: nil, width: canvasW, height: canvasH,
                          bitsPerComponent: 8, bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    next.interpolationQuality = .high
    next.draw(blurredCG, in: canvasOriginRect)
    next.draw(sourceImage, in: drawSourceRect)  // re-pin layer to sharp
    if let img = next.makeImage() { current = img }
}

let prepCtx = CGContext(data: nil, width: canvasW, height: canvasH,
                         bitsPerComponent: 8, bytesPerRow: 0, space: space,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
prepCtx.interpolationQuality = .high
prepCtx.draw(current, in: canvasOriginRect)

// Light noise overlay (10%) so the model has texture to refine into detail.
let noise = makeNoise(width: canvasW, height: canvasH)
prepCtx.saveGState()
prepCtx.setAlpha(0.10)
prepCtx.draw(noise, in: canvasOriginRect)
prepCtx.restoreGState()

// Re-pin the sharp composite over the layer area (in case the noise overlay
// touched it).
let preserveCG = CGRect(x: layerBounds.minX,
                        y: canvasSize.height - layerBounds.maxY,
                        width: layerBounds.width, height: layerBounds.height)
prepCtx.saveGState()
prepCtx.clip(to: preserveCG)
prepCtx.draw(composed, in: canvasOriginRect)
prepCtx.restoreGState()
let prepared = prepCtx.makeImage()!
pngWrite(prepared, name: "02-prepared-context")

let maskCtx = CGContext(data: nil, width: canvasW, height: canvasH,
                         bitsPerComponent: 8, bytesPerRow: 0, space: space,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
maskCtx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
maskCtx.fill(CGRect(x: 0, y: 0, width: canvasW, height: canvasH))
maskCtx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
maskCtx.fill(preserveCG)
let canvasMask = maskCtx.makeImage()!
pngWrite(canvasMask, name: "03-mask")

// MARK: - tile slots (mirrors GenerativeFillCoordinator.runExpandTiled)

let tw: CGFloat = 512, th: CGFloat = 512
func slotsFor(canvas: CGFloat, tile: CGFloat, minOverlap: CGFloat = 64) -> [CGFloat] {
    if canvas <= tile { return [max(0, (canvas - tile) / 2)] }
    let span = canvas - tile
    let maxStep = max(1, tile - minOverlap)
    let n = max(2, Int(ceil(span / maxStep)) + 1)
    let step = span / CGFloat(n - 1)
    return (0..<n).map { CGFloat($0) * step }
}
let vSlots = slotsFor(canvas: canvasSize.height, tile: th)
let hSlots = slotsFor(canvas: canvasSize.width, tile: tw)

let canvasRect = CGRect(x: 0, y: 0, width: canvasSize.width, height: canvasSize.height)
var tileRects: [(rect: CGRect, label: String)] = []
let bandT = ly, bandB = canvasSize.height - ly - lh, bandL = lx, bandR = canvasSize.width - lx - lw
let bandThreshold: CGFloat = 8
if bandL > bandThreshold {
    for (i, vy) in vSlots.enumerated() {
        tileRects.append((CGRect(x: 0, y: vy, width: tw, height: th).intersection(canvasRect), "left-\(i)"))
    }
}
if bandR > bandThreshold {
    for (i, vy) in vSlots.enumerated() {
        tileRects.append((CGRect(x: max(0, canvasSize.width - tw), y: vy, width: tw, height: th).intersection(canvasRect), "right-\(i)"))
    }
}
if bandT > bandThreshold {
    for (i, hx) in hSlots.enumerated() {
        tileRects.append((CGRect(x: hx, y: 0, width: tw, height: th).intersection(canvasRect), "top-\(i)"))
    }
}
if bandB > bandThreshold {
    for (i, hx) in hSlots.enumerated() {
        tileRects.append((CGRect(x: hx, y: max(0, canvasSize.height - th), width: tw, height: th).intersection(canvasRect), "bottom-\(i)"))
    }
}
print("Tiles:    \(tileRects.count) — \(tileRects.map(\.label).joined(separator: ", "))")

// MARK: - load SD pipeline

print("\nLoading SD pipeline…")
let mlConfig = MLModelConfiguration()
mlConfig.computeUnits = .cpuAndGPU  // ANE path tends to fail on this model variant
let pipeline: StableDiffusionPipeline
do {
    pipeline = try StableDiffusionPipeline(
        resourcesAt: modelDir,
        controlNet: [],
        configuration: mlConfig,
        disableSafety: true,
        reduceMemory: true)
    try pipeline.loadResources()
    print("Pipeline ready.")
} catch {
    FileHandle.standardError.write(Data("Pipeline init failed: \(error)\n".utf8))
    exit(4)
}

// MARK: - run model on each tile, composite back

let outCtx = CGContext(data: nil, width: canvasW, height: canvasH,
                        bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
outCtx.interpolationQuality = .high

// Seed per band so all tiles within the same band (e.g. left-0, left-1, left-2)
// share consistent noise → less drift between adjacent tile contents.
var bandSeeds: [String: UInt32] = [:]
func bandKey(_ label: String) -> String {
    String(label.split(separator: "-").first ?? Substring(label))
}

// For each tile, decide which edges to feather based on which neighbors share the band.
let tileLabels = tileRects.map(\.label)
func tileFadeFlags(label: String) -> (top: Bool, bottom: Bool, left: Bool, right: Bool) {
    let parts = label.split(separator: "-")
    guard parts.count == 2,
          let idx = Int(parts[1]) else { return (false, false, false, false) }
    let band = String(parts[0])  // left/right/top/bottom
    let prevExists = tileLabels.contains("\(band)-\(idx - 1)")
    let nextExists = tileLabels.contains("\(band)-\(idx + 1)")
    if band == "left" || band == "right" {
        // vertical band → feather top/bottom toward neighbors
        return (top: prevExists, bottom: nextExists, left: false, right: false)
    } else {
        // horizontal band → feather left/right toward neighbors
        return (top: false, bottom: false, left: prevExists, right: nextExists)
    }
}

let fadeSize = Int((512 - 284) / 2)  // half the overlap = 114 px → meet at midpoint

for (idx, tr) in tileRects.enumerated() {
    print("\n[Tile \(idx + 1)/\(tileRects.count)] \(tr.label) at (\(Int(tr.rect.minX)),\(Int(tr.rect.minY)))")
    guard let tileIn = cropTopDown(prepared, to: tr.rect),
          let tileMask = cropTopDown(canvasMask, to: tr.rect) else {
        print("  crop failed — skip"); continue
    }
    let resizedIn = resize(tileIn, to: CGSize(width: 512, height: 512)) ?? tileIn
    pngWrite(resizedIn, name: "tile-\(tr.label)-in")
    pngWrite(tileMask, name: "tile-\(tr.label)-mask")

    let key = bandKey(tr.label)
    let seed = bandSeeds[key] ?? UInt32.random(in: 0..<UInt32.max)
    bandSeeds[key] = seed

    var pcfg = StableDiffusionPipeline.Configuration(prompt: prompt)
    pcfg.imageCount = 1
    pcfg.stepCount = 25
    pcfg.seed = seed
    pcfg.guidanceScale = 7.5
    pcfg.startingImage = resizedIn
    pcfg.strength = strength
    pcfg.schedulerType = .dpmSolverMultistepScheduler
    pcfg.useDenoisedIntermediates = false

    do {
        let images = try pipeline.generateImages(configuration: pcfg) { stepInfo in
            if stepInfo.step % 5 == 0 {
                print("    step \(stepInfo.step)/\(pcfg.stepCount)")
            }
            return true
        }
        guard let result = images.first.flatMap({ $0 }) else { print("  no image"); continue }
        pngWrite(result, name: "tile-\(tr.label)-result")
        let resizedOut = resize(result, to: tr.rect.size) ?? result
        let clipped = clipToMask(resizedOut, mask: tileMask)
        // Cross-fade with neighbors so adjacent tile boundaries don't show.
        let flags = tileFadeFlags(label: tr.label)
        let faded = applyTileFade(clipped,
                                   fadeTop: flags.top, fadeBottom: flags.bottom,
                                   fadeLeft: flags.left, fadeRight: flags.right,
                                   fadeSize: fadeSize)
        pngWrite(faded, name: "tile-\(tr.label)-clipped")
        let drawDest = CGRect(x: tr.rect.minX,
                              y: canvasSize.height - tr.rect.maxY,
                              width: tr.rect.width, height: tr.rect.height)
        outCtx.draw(faded, in: drawDest)
    } catch {
        FileHandle.standardError.write(Data("  generation failed: \(error)\n".utf8))
    }
}

if let combined = outCtx.makeImage() {
    pngWrite(combined, name: "06-fillOnly-combined")
}

// Final: overlay the fill on top of the original composite for visual confirmation.
let finalCtx = CGContext(data: nil, width: canvasW, height: canvasH,
                          bitsPerComponent: 8, bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
finalCtx.draw(composed, in: CGRect(x: 0, y: 0, width: canvasW, height: canvasH))
if let combined = outCtx.makeImage() {
    finalCtx.draw(combined, in: CGRect(x: 0, y: 0, width: canvasW, height: canvasH))
}
let finalImg = finalCtx.makeImage()!
pngWrite(finalImg, name: "07-final-composite")

print("\nDone. Inspect /tmp/expand_full_test/")
