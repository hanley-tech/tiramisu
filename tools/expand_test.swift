#!/usr/bin/env swift

// Standalone test harness for the Generative Fill Expand prep pipeline.
//
// Re-implements the relevant geometry from GenerativeFillCoordinator so we can
// validate prep without launching the app or running the SD model:
//   • layer placement (fit-scale into canvas)
//   • prepared context image (composite + noise-filled bands)
//   • outpaint mask (white outside layer, black inside)
//   • tile placement (covers full canvas with overlapping 512² tiles)
//   • per-tile crops of input + mask
//
// Usage:
//   swift tools/expand_test.swift <image> <canvasW> <canvasH> [<sourceMaxDim>]
//
// If <sourceMaxDim> is given and the image is larger, the image is first
// resized so its longest edge equals that value — useful when you want to
// simulate "smaller source on a bigger canvas" using a finished thumbnail.
//
// All artifacts land in /tmp/expand_test/. Read the PNGs to inspect.

import Foundation
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers

// MARK: - args

let args = CommandLine.arguments
guard args.count >= 4,
      let canvasW = Int(args[2]),
      let canvasH = Int(args[3])
else {
    FileHandle.standardError.write(Data("usage: expand_test <image> <canvasW> <canvasH> [<sourceMaxDim>]\n".utf8))
    exit(2)
}
let imagePath = args[1]
let sourceMaxDim: Int? = args.count >= 5 ? Int(args[4]) : nil
let canvasSize = CGSize(width: canvasW, height: canvasH)
let outDir = URL(fileURLWithPath: "/tmp/expand_test")
try? FileManager.default.removeItem(at: outDir)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

// MARK: - load image

guard let imgSource = CGImageSourceCreateWithURL(URL(fileURLWithPath: imagePath) as CFURL, nil),
      var sourceImage = CGImageSourceCreateImageAtIndex(imgSource, 0, nil)
else {
    FileHandle.standardError.write(Data("Could not load \(imagePath)\n".utf8))
    exit(1)
}

print("Source: \(sourceImage.width)x\(sourceImage.height)")
print("Canvas: \(canvasW)x\(canvasH)")

// Optional pre-resize so the source has empty bands when placed in the canvas.
if let maxDim = sourceMaxDim {
    let longest = max(sourceImage.width, sourceImage.height)
    if longest > maxDim {
        let scale = Double(maxDim) / Double(longest)
        let nw = Int(Double(sourceImage.width) * scale)
        let nh = Int(Double(sourceImage.height) * scale)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: nw, height: nh,
                             bitsPerComponent: 8, bytesPerRow: 0, space: space,
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        ctx.draw(sourceImage, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        sourceImage = ctx.makeImage()!
        print("Pre-resized source to: \(nw)x\(nh) (sourceMaxDim=\(maxDim))")
    }
}

// MARK: - layer placement (fit-scale into canvas, centered)

let scale = min(canvasSize.width / CGFloat(sourceImage.width),
                canvasSize.height / CGFloat(sourceImage.height))
let lw = CGFloat(sourceImage.width) * scale
let lh = CGFloat(sourceImage.height) * scale
let lx = (canvasSize.width - lw) / 2
let ly = (canvasSize.height - lh) / 2
let layerBounds = CGRect(x: lx, y: ly, width: lw, height: lh)
print("Layer bounds (top-down): origin=(\(lx),\(ly)) size=(\(lw)x\(lh))")
let bandL = lx
let bandR = canvasSize.width - (lx + lw)
let bandT = ly
let bandB = canvasSize.height - (ly + lh)
print("Bands: L=\(bandL) R=\(bandR) T=\(bandT) B=\(bandB)")

// MARK: - helpers

func pngWrite(_ image: CGImage, name: String) {
    let url = outDir.appendingPathComponent("\(name).png")
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        return
    }
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
        let r = UInt8((state &* 6364136223846793005) >> 56)
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        let g = UInt8((state &* 6364136223846793005) >> 56)
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        let b = UInt8((state &* 6364136223846793005) >> 56)
        bytes[i] = r; bytes[i+1] = g; bytes[i+2] = b; bytes[i+3] = 255
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

// MARK: - 1) "composite" — image rendered into canvas at layer bounds, dark navy bg

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let composedCtx = CGContext(data: nil, width: canvasW, height: canvasH,
                             bitsPerComponent: 8, bytesPerRow: 0, space: space,
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
composedCtx.interpolationQuality = .high
// Dark navy canvas background (matches DocumentStore default).
composedCtx.setFillColor(CGColor(srgbRed: 0.05, green: 0.07, blue: 0.12, alpha: 1))
composedCtx.fill(CGRect(x: 0, y: 0, width: canvasW, height: canvasH))
// Image rendered at layer bounds (CG y-up flip).
let drawRect = CGRect(x: layerBounds.minX,
                      y: canvasSize.height - layerBounds.maxY,
                      width: layerBounds.width,
                      height: layerBounds.height)
composedCtx.draw(sourceImage, in: drawRect)
let composed = composedCtx.makeImage()!
pngWrite(composed, name: "01-composed")

// MARK: - 2) prepared context — composite inside layer, noise outside

let prepCtx = CGContext(data: nil, width: canvasW, height: canvasH,
                         bitsPerComponent: 8, bytesPerRow: 0, space: space,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
prepCtx.interpolationQuality = .high
// Fill with random noise first (everywhere).
let noise = makeNoise(width: canvasW, height: canvasH)
prepCtx.draw(noise, in: CGRect(x: 0, y: 0, width: canvasW, height: canvasH))
// Clip to layer bounds and overdraw composite — noise survives only in bands.
let preserveCG = CGRect(x: layerBounds.minX,
                        y: canvasSize.height - layerBounds.maxY,
                        width: layerBounds.width,
                        height: layerBounds.height)
prepCtx.saveGState()
prepCtx.clip(to: preserveCG)
prepCtx.draw(composed, in: CGRect(x: 0, y: 0, width: canvasW, height: canvasH))
prepCtx.restoreGState()
let prepared = prepCtx.makeImage()!
pngWrite(prepared, name: "02-prepared-context")

// MARK: - 3) outpaint mask — white outside layer, black inside

let maskCtx = CGContext(data: nil, width: canvasW, height: canvasH,
                         bitsPerComponent: 8, bytesPerRow: 0, space: space,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
maskCtx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
maskCtx.fill(CGRect(x: 0, y: 0, width: canvasW, height: canvasH))
maskCtx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
maskCtx.fill(preserveCG)
let mask = maskCtx.makeImage()!
pngWrite(mask, name: "03-mask")

// Quick coverage check: white pixel proportion should match band area.
do {
    let dataProvider = mask.dataProvider!
    let cfdata = dataProvider.data!
    let ptr = CFDataGetBytePtr(cfdata)!
    let count = CFDataGetLength(cfdata)
    var whiteCount = 0
    for i in stride(from: 0, to: count, by: 4) {
        // Pixel is white if R is high.
        if ptr[i] > 200 { whiteCount += 1 }
    }
    let total = canvasW * canvasH
    let pct = Double(whiteCount) / Double(total) * 100
    let expected = (canvasSize.width * canvasSize.height - layerBounds.width * layerBounds.height) / (canvasSize.width * canvasSize.height) * 100
    print("Mask white coverage: \(String(format: "%.1f%%", pct)) (expected ~\(String(format: "%.1f%%", expected)))")
}

// MARK: - 4) tile placement (mirrors runExpandTiled)

let tw: CGFloat = 512, th: CGFloat = 512

func slotsFor(canvas: CGFloat, tile: CGFloat, minOverlap: CGFloat = 64) -> [CGFloat] {
    if canvas <= tile { return [max(0, (canvas - tile) / 2)] }
    let span = canvas - tile
    let maxStep = max(1, tile - minOverlap)
    let n = max(2, Int(ceil(span / maxStep)) + 1)
    let step = span / CGFloat(n - 1)
    return (0..<n).map { CGFloat($0) * step }
}
func verticalSlots() -> [CGFloat] { slotsFor(canvas: canvasSize.height, tile: th) }
func horizontalSlots() -> [CGFloat] { slotsFor(canvas: canvasSize.width, tile: tw) }

let canvasRect = CGRect(x: 0, y: 0, width: canvasSize.width, height: canvasSize.height)
var tileRects: [(rect: CGRect, label: String)] = []
let bandThreshold: CGFloat = 8
let vSlots = verticalSlots()
let hSlots = horizontalSlots()

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

print("Tiles: \(tileRects.count) — \(tileRects.map(\.label).joined(separator: ", "))")
for tr in tileRects {
    print("  \(tr.label): origin=(\(Int(tr.rect.minX)),\(Int(tr.rect.minY))) size=(\(Int(tr.rect.width))x\(Int(tr.rect.height)))")
    if let inImg = cropTopDown(prepared, to: tr.rect) {
        pngWrite(inImg, name: "04-tile-\(tr.label)-in")
    }
    if let mImg = cropTopDown(mask, to: tr.rect) {
        pngWrite(mImg, name: "04-tile-\(tr.label)-mask")
    }
}

// MARK: - 5) coverage assertion: the *union* of tile rects must cover every band pixel

let bandsCtx = CGContext(data: nil, width: canvasW, height: canvasH,
                          bitsPerComponent: 8, bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
bandsCtx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
bandsCtx.fill(CGRect(x: 0, y: 0, width: canvasW, height: canvasH))
bandsCtx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
bandsCtx.fill(preserveCG)
// Now overlay tile rects in green.
bandsCtx.setFillColor(CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 0.5))
for tr in tileRects {
    let r = CGRect(x: tr.rect.minX,
                   y: canvasSize.height - tr.rect.maxY,
                   width: tr.rect.width, height: tr.rect.height)
    bandsCtx.fill(r)
}
let coverageImg = bandsCtx.makeImage()!
pngWrite(coverageImg, name: "05-tile-coverage")

// Compute red-not-green pixels: red = band, green = covered. Bug: red survives.
do {
    let prov = coverageImg.dataProvider!
    let cfdata = prov.data!
    let ptr = CFDataGetBytePtr(cfdata)!
    let count = CFDataGetLength(cfdata)
    var uncovered = 0
    for i in stride(from: 0, to: count, by: 4) {
        let r = ptr[i], g = ptr[i+1], b = ptr[i+2]
        // Pure red (not green-tinted) = band pixel not covered by any tile.
        if r > 200 && g < 80 && b < 80 { uncovered += 1 }
    }
    if uncovered == 0 {
        print("✓ Tile coverage: every band pixel is inside at least one tile")
    } else {
        print("✗ Tile coverage: \(uncovered) band pixels uncovered (see 05-tile-coverage.png — pure red = uncovered)")
    }
}

print("\nDone. Inspect /tmp/expand_test/")
