import Foundation
import CoreGraphics
import CoreML
import StableDiffusion
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// On-device generative fill via Apple's `ml-stable-diffusion` package using a
/// SD-1.5 inpainting model. Models live under
/// `~/Library/Application Support/Thumbz/Models/sd15-inpaint/` as a directory
/// of `.mlmodelc` bundles produced by Apple's converter (or downloaded as a
/// pre-converted package).
struct LocalSDInpaintService: GenerativeFillService {
    let modelDirectory: URL
    let computeUnits: MLComputeUnits
    let strength: Float          // i2i strength (0…1). Lower = preserve more input.

    /// Local SD-1.5 internally rescales to 512×512. Tell the coordinator to
    /// tile its inputs at this size so we never destroy aspect ratio.
    var preferredInputSize: CGSize? { CGSize(width: 512, height: 512) }

    init(modelDirectory: URL, computeUnits: MLComputeUnits = .all, strength: Float = 0.85) {
        // .all lets Core ML route each layer to ANE/GPU/CPU based on what
        // each can actually run. The pure-ANE path occasionally fails on
        // certain SD-1.5 layers with "Unable to compute the asynchronous
        // prediction using ML Program."
        self.modelDirectory = modelDirectory
        self.computeUnits = computeUnits
        self.strength = strength
    }

    private func buildPipeline(units: MLComputeUnits) throws -> StableDiffusionPipeline {
        let config = MLModelConfiguration()
        config.computeUnits = units
        let pipeline = try StableDiffusionPipeline(
            resourcesAt: modelDirectory,
            controlNet: [],
            configuration: config,
            disableSafety: true,
            reduceMemory: true)
        try pipeline.loadResources()
        return pipeline
    }

    static func resize(_ image: CGImage, to size: CGSize) -> CGImage? {
        if image.width == Int(size.width) && image.height == Int(size.height) { return image }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        return ctx.makeImage()
    }

    static var defaultModelDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Thumbz/Models/sd15-inpaint", isDirectory: true)
    }

    static var isModelInstalled: Bool {
        let dir = defaultModelDirectory
        let unet = dir.appendingPathComponent("Unet.mlmodelc")
        return FileManager.default.fileExists(atPath: unet.path)
    }

    /// Reads the version.json we drop next to the model on install.
    static var installedVersion: String? {
        let url = defaultModelDirectory.appendingPathComponent("thumbz-version.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json["version"] as? String
    }

    static func uninstall() throws {
        try FileManager.default.removeItem(at: defaultModelDirectory)
    }

    static func installedSizeMB() -> Double {
        let url = defaultModelDirectory
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
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
        guard FileManager.default.fileExists(atPath: modelDirectory.path) else {
            throw GenerativeFillError.predictionFailed("Local SD model not installed at \(modelDirectory.path). Run AI → Generative Fill → Install Local Model.")
        }
        // SD-1.5 expects 512×512. Resize the input + mask before encoding;
        // the GenerativeFillCoordinator already scales the result back to the
        // canvas dimensions for the new layer.
        progress("Resizing input to 512×512…")
        let target = CGSize(width: 512, height: 512)
        guard let sized = Self.resize(image, to: target) else {
            throw GenerativeFillError.predictionFailed("Could not resize input image")
        }

        // Try the configured compute units first; if Core ML rejects the model
        // ("Unable to compute the asynchronous prediction using ML Program"),
        // retry on .cpuAndGPU which is the most permissive path.
        let primaryUnits = computeUnits
        let fallbackUnits: MLComputeUnits = .cpuAndGPU
        let pipeline: StableDiffusionPipeline
        do {
            progress("Loading model on Neural Engine…")
            pipeline = try buildPipeline(units: primaryUnits)
        } catch {
            tlog("Pipeline build failed on \(primaryUnits): \(error). Retrying on \(fallbackUnits)")
            progress("Retrying on GPU…")
            pipeline = try buildPipeline(units: fallbackUnits)
        }
        progress("Model loaded")

        progress("Generating…")
        // Apple's pipeline only exposes image-to-image (no native masked inpainting).
        // We feed the source as `startingImage` at high strength, regenerate, and let
        // GenerativeFillCoordinator composite the result back through the mask.
        // Mask-aware inpainting models (FLUX-Fill, SD-Inpaint) would be better;
        // until those land in the Swift package this is the closest local approximation.
        var pipelineConfig = StableDiffusionPipeline.Configuration(prompt: prompt.isEmpty ? "high quality, photorealistic" : prompt)
        pipelineConfig.imageCount = 1
        pipelineConfig.stepCount = 25
        pipelineConfig.seed = UInt32.random(in: 0..<UInt32.max)
        pipelineConfig.guidanceScale = 7.5
        pipelineConfig.startingImage = sized
        pipelineConfig.strength = strength
        pipelineConfig.schedulerType = .dpmSolverMultistepScheduler
        pipelineConfig.useDenoisedIntermediates = false
        _ = mask  // mask compositing happens after the pipeline returns

        let images: [CGImage?]
        do {
            images = try pipeline.generateImages(configuration: pipelineConfig) { stepInfo in
                progress("Step \(stepInfo.step) of \(pipelineConfig.stepCount)")
                return true
            }
        } catch {
            tlog("Sampling failed on primary compute units: \(error). Retrying on cpuAndGPU.")
            progress("Sampling failed, retrying on GPU…")
            let cpuGpuPipeline = try buildPipeline(units: .cpuAndGPU)
            images = try cpuGpuPipeline.generateImages(configuration: pipelineConfig) { stepInfo in
                progress("Step \(stepInfo.step) of \(pipelineConfig.stepCount) (GPU)")
                return true
            }
        }
        guard let result = images.first.flatMap({ $0 }) else {
            throw GenerativeFillError.predictionFailed("Pipeline returned no images")
        }
        return result
    }
}

/// Tiny model-installer helper. Downloads a pre-compiled SD-1.5 inpainting
/// Core ML bundle from Hugging Face the first time, unzips, and stores it at
/// the expected directory.
@MainActor
enum LocalSDInstaller {
    /// Bumped whenever the model URL or expected layout changes.
    /// v2 swaps from a 9-channel SD-inpaint UNet (which Apple's Swift pipeline
    /// can't drive — its scheduler asserts on shape mismatch) to the standard
    /// 4-channel SD-1.5 model. We achieve fill behavior via image-to-image +
    /// post-mask compositing in the coordinator instead of true masked inpaint.
    static let installedModelVersion = "sd-1.5-i2i.v2"

    /// Apple's official Core ML-compiled SD-1.5 (4-channel UNet, supported).
    static let baseHFURL = "https://huggingface.co/apple/coreml-stable-diffusion-v1-5/resolve/main/original/compiled"
    static let defaultZipURL = URL(string: baseHFURL)!  // unused — we always do per-file fetch
    // Apple's compiled SD-1.5 ships these directories.
    static let bundleNames = [
        "TextEncoder.mlmodelc",
        "Unet.mlmodelc",
        "VAEDecoder.mlmodelc",
        "VAEEncoder.mlmodelc",
        "SafetyChecker.mlmodelc"
    ]
    static let auxFiles = ["merges.txt", "vocab.json"]

    static func install(force: Bool = false,
                          progress: @escaping (String, Double) -> Void) async throws {
        let dest = LocalSDInpaintService.defaultModelDirectory
        if !force && LocalSDInpaintService.isModelInstalled
            && LocalSDInpaintService.installedVersion == installedModelVersion {
            progress("Already installed (v\(installedModelVersion))", 1.0)
            return
        }
        // If switching versions, wipe the old directory first so stale weights
        // don't get mixed with new ones.
        if LocalSDInpaintService.isModelInstalled
            && LocalSDInpaintService.installedVersion != installedModelVersion {
            try? FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        // Always per-file from Apple's repo (no top-level zip ships).
        try await installFromFiles(dest: dest, progress: progress)
    }

    private static func installFromZip(dest: URL, progress: @escaping (String, Double) -> Void) async throws {
        progress("Downloading SD model zip (~1.7 GB)…", 0)
        let tmpURL = try await downloadWithProgress(url: defaultZipURL) { fraction, sofarMB, totalMB in
            // Reserve 0–0.85 of the bar for download, leave 0.15 for unzip+install.
            let displayed = fraction * 0.85
            progress("Downloading… \(Int(sofarMB)) / \(Int(totalMB)) MB", displayed)
        }

        progress("Unzipping…", 0.85)
        let unzipDir = FileManager.default.temporaryDirectory.appendingPathComponent("thumbz-sd-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: unzipDir, withIntermediateDirectories: true)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        proc.arguments = ["-q", tmpURL.path, "-d", unzipDir.path]
        try proc.run(); proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            throw GenerativeFillError.predictionFailed("Unzip failed (status \(proc.terminationStatus))")
        }

        progress("Installing…", 0.95)
        try moveBundles(from: unzipDir, to: dest)
        try? FileManager.default.removeItem(at: unzipDir)
        try? FileManager.default.removeItem(at: tmpURL)
        try writeVersion(to: dest)
        progress("Model installed", 1.0)
    }

    private static func writeVersion(to dest: URL) throws {
        let payload: [String: Any] = [
            "version": installedModelVersion,
            "installed": ISO8601DateFormatter().string(from: Date()),
            "source": defaultZipURL.absoluteString
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
        try data.write(to: dest.appendingPathComponent("thumbz-version.json"), options: .atomic)
    }

    private static func installFromFiles(dest: URL,
                                          progress: @escaping (String, Double) -> Void) async throws {
        let base = baseHFURL
        // Each bundle contains: coremldata.bin, metadata.json, model.mil, weights/weight.bin, analytics/coremldata.bin
        let perBundleFiles = [
            "coremldata.bin", "metadata.json", "model.mil",
            "weights/weight.bin", "analytics/coremldata.bin"
        ]
        let total = bundleNames.count * perBundleFiles.count + auxFiles.count
        var done = 0
        for bundle in bundleNames {
            for file in perBundleFiles {
                done += 1
                let frac = Double(done) / Double(total)
                progress("\(bundle) — \(file)", frac)
                let url = URL(string: "\(base)/\(bundle)/\(file)")!
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
            let url = URL(string: "\(base)/\(aux)")!
            let dst = dest.appendingPathComponent(aux)
            let (tmp, _) = try await URLSession.shared.download(from: url)
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.moveItem(at: tmp, to: dst)
        }
        try writeVersion(to: dest)
        progress("Model installed", 1.0)
    }

    /// URLSessionDownloadTask wrapped as async/await with byte-by-byte progress.
    private static func downloadWithProgress(
        url: URL,
        progress: @escaping (_ fraction: Double, _ sofarMB: Double, _ totalMB: Double) -> Void
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            let delegate = DownloadProgressDelegate(progress: progress, continuation: cont)
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = 120
            cfg.timeoutIntervalForResource = 60 * 60   // up to 1 hour for huge models
            let session = URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)
            delegate.session = session
            let task = session.downloadTask(with: url)
            task.resume()
        }
    }

    /// Delegate that bridges URLSessionDownloadTask progress callbacks into a
    /// CheckedContinuation. NSObject + URLSessionDownloadDelegate.
    private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let progress: (Double, Double, Double) -> Void
        var continuation: CheckedContinuation<URL, Error>?
        var session: URLSession?

        init(progress: @escaping (Double, Double, Double) -> Void,
             continuation: CheckedContinuation<URL, Error>) {
            self.progress = progress
            self.continuation = continuation
        }

        func urlSession(_ session: URLSession,
                         downloadTask: URLSessionDownloadTask,
                         didWriteData bytesWritten: Int64,
                         totalBytesWritten: Int64,
                         totalBytesExpectedToWrite: Int64) {
            guard totalBytesExpectedToWrite > 0 else {
                progress(0, Double(totalBytesWritten) / 1_048_576, 0)
                return
            }
            let frac = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            let sofar = Double(totalBytesWritten) / 1_048_576
            let total = Double(totalBytesExpectedToWrite) / 1_048_576
            progress(frac, sofar, total)
        }

        func urlSession(_ session: URLSession,
                         downloadTask: URLSessionDownloadTask,
                         didFinishDownloadingTo location: URL) {
            // The temp file vanishes after this method returns — copy it.
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent("thumbz-dl-\(UUID().uuidString)")
            do {
                try FileManager.default.copyItem(at: location, to: copy)
                continuation?.resume(returning: copy)
            } catch {
                continuation?.resume(throwing: error)
            }
            continuation = nil
            self.session?.invalidateAndCancel()
        }

        func urlSession(_ session: URLSession,
                         task: URLSessionTask,
                         didCompleteWithError error: Error?) {
            if let error, let cont = continuation {
                cont.resume(throwing: error)
                continuation = nil
                self.session?.invalidateAndCancel()
            }
        }
    }

    private static func moveBundles(from src: URL, to dest: URL) throws {
        // Find any directory named "*.mlmodelc" anywhere under src and move it.
        let fm = FileManager.default
        let enumerator = fm.enumerator(at: src, includingPropertiesForKeys: [.isDirectoryKey])
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "mlmodelc" {
                let target = dest.appendingPathComponent(url.lastPathComponent)
                try? fm.removeItem(at: target)
                try fm.moveItem(at: url, to: target)
                enumerator?.skipDescendants()
            }
        }
        // Aux files (vocab.json / merges.txt)
        for aux in auxFiles {
            let candidate = src.appendingPathComponent(aux)
            if fm.fileExists(atPath: candidate.path) {
                let target = dest.appendingPathComponent(aux)
                try? fm.removeItem(at: target)
                try fm.moveItem(at: candidate, to: target)
            }
        }
    }
}
