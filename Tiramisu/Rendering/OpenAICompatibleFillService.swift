import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Implements GenerativeFillService via the OpenAI images/edits endpoint.
///
/// Mask convention mismatch: internally Tiramisu uses white=fill, black=preserve.
/// OpenAI's images/edits expects a PNG where *transparent* areas indicate fill.
/// This service converts the mask before sending.
struct OpenAICompatibleFillService: GenerativeFillService, Sendable {

    let baseURL: String
    let apiKey: String
    let model: String
    let authStyle: OpenAICompatibleProvider.AuthStyle

    var preferredInputSize: CGSize? { nil }  // mask-aware, no tiling needed
    var needsPrepFill: Bool { true }         // pre-fill bands before sending

    private static let supportedSizes: [(w: Int, h: Int, label: String)] = [
        (1024, 1024, "1024x1024"),
        (1536, 1024, "1536x1024"),
        (1024, 1536, "1024x1536"),
    ]

    private var isAzure: Bool { authStyle == .azureAPIKey }

    private var editsURL: String {
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        if isAzure {
            return "\(base)/openai/deployments/\(model)/images/edits?api-version=2025-04-01-preview"
        } else {
            return "\(base)/v1/images/edits"
        }
    }

    func fill(image: CGImage,
              mask: CGImage,
              prompt: String,
              progress: @Sendable @escaping (String) -> Void = { _ in }) async throws -> CGImage {
        let (targetW, targetH, sizeLabel) = Self.bestSize(for: image)
        let host = isAzure ? "Azure OpenAI" : "OpenAI"
        progress("[\(host)] \(image.width)×\(image.height) → \(sizeLabel) · \(model)")

        let resizedImage = resize(image, toWidth: targetW, height: targetH) ?? image
        let resizedMask  = resize(mask,  toWidth: targetW, height: targetH) ?? mask

        // Convert mask: white (fill) → transparent; black (preserve) → opaque.
        guard let oaiMask = convertMaskToOpenAI(resizedMask) else {
            throw ProviderError.invalidInput("Could not convert mask for OpenAI format")
        }

        guard let imgPNG  = encodePNG(resizedImage),
              let maskPNG = encodePNG(oaiMask) else {
            throw ProviderError.invalidInput("Could not encode image/mask as PNG")
        }

        guard let url = URL(string: editsURL) else {
            throw ProviderError.invalidInput("Bad endpoint URL: \(editsURL)")
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        func append(_ s: String) { body.append(Data(s.utf8)) }
        func field(_ name: String, _ value: String) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }

        // image
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"image\"; filename=\"image.png\"\r\n")
        append("Content-Type: image/png\r\n\r\n")
        body.append(imgPNG)
        append("\r\n")

        // mask
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"mask\"; filename=\"mask.png\"\r\n")
        append("Content-Type: image/png\r\n\r\n")
        body.append(maskPNG)
        append("\r\n")

        field("prompt", prompt)
        field("n", "1")
        field("size", sizeLabel)
        field("quality", "high")
        if !isAzure { field("model", model) }
        append("--\(boundary)--\r\n")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if isAzure {
            req.setValue(apiKey, forHTTPHeaderField: "api-key")
        } else {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = body
        req.timeoutInterval = 300

        progress("[\(host)] Sending fill request…")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw ProviderError.network(error)
        }

        let http = response as! HTTPURLResponse
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ProviderError.invalidKey
        }
        if http.statusCode == 429 {
            let detail = String(data: data, encoding: .utf8) ?? "rate limited"
            throw ProviderError.quotaExceeded(detail: detail)
        }
        guard http.statusCode == 200 else {
            let detail = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw ProviderError.unknown("\(host) fill error: \(detail)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArr = json["data"] as? [[String: Any]],
              let first = dataArr.first,
              let b64 = first["b64_json"] as? String,
              let imgData = Data(base64Encoded: b64) else {
            throw ProviderError.decodeFailure("Unexpected response shape from \(host)")
        }

        guard let src = CGImageSourceCreateWithData(imgData as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw ProviderError.decodeFailure("Could not decode \(host) fill output")
        }
        progress("[\(host)] Done")
        return retagAsSRGB(cg)
    }

    // MARK: - Helpers

    private static func bestSize(for image: CGImage) -> (Int, Int, String) {
        let aspect = Double(image.width) / Double(image.height)
        return supportedSizes.min(by: { a, b in
            abs(Double(a.w) / Double(a.h) - aspect) < abs(Double(b.w) / Double(b.h) - aspect)
        }) ?? (1024, 1024, "1024x1024")
    }

    /// White (fill in FLUX convention) → transparent; black → opaque white.
    /// OpenAI images/edits interprets transparent pixels as the fill region.
    private func convertMaskToOpenAI(_ mask: CGImage) -> CGImage? {
        let w = mask.width, h = mask.height
        let bytesPerRow = w * 4
        var pixels = [UInt8](repeating: 0, count: h * bytesPerRow)

        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let readCtx = CGContext(data: &pixels, width: w, height: h,
                                     bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                     space: space,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        readCtx.draw(mask, in: CGRect(x: 0, y: 0, width: w, height: h))

        // pixels is RGBA8 premultiplied. The mask is grayscale so R≈G≈B≈lum.
        // We want alpha = 255 − lum (white=fill → alpha=0 transparent).
        // In premultiplied format, opaque white is (255,255,255,255) and fully
        // transparent is (0,0,0,0).
        for i in 0..<(w * h) {
            let base = i * 4
            let lum = pixels[base]       // R channel (mask is grayscale)
            let a = UInt8(255 - Int(lum))
            pixels[base]     = a         // premultiplied R = 255*(a/255) = a
            pixels[base + 1] = a
            pixels[base + 2] = a
            pixels[base + 3] = a
        }

        guard let writeCtx = CGContext(data: &pixels, width: w, height: h,
                                       bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                       space: space,
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        return writeCtx.makeImage()
    }

    private func resize(_ image: CGImage, toWidth w: Int, height h: Int) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    private func encodePNG(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    private func retagAsSRGB(_ raw: CGImage) -> CGImage {
        guard let provider = raw.dataProvider,
              let data = provider.data,
              let dp = CGDataProvider(data: data),
              let srgb = CGColorSpace(name: CGColorSpace.sRGB) else { return raw }
        return CGImage(
            width: raw.width, height: raw.height,
            bitsPerComponent: raw.bitsPerComponent,
            bitsPerPixel: raw.bitsPerPixel,
            bytesPerRow: raw.bytesPerRow,
            space: srgb, bitmapInfo: raw.bitmapInfo,
            provider: dp, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent
        ) ?? raw
    }
}
