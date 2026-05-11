import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Calls any OpenAI-compatible images/edits endpoint.
/// Works with:
///   • Direct OpenAI (api.openai.com) — Bearer token auth, model in body
///   • Azure OpenAI (*.cognitiveservices.azure.com) — api-key auth,
///     deployment name in URL path
///   • Any other OpenAI-compatible host — same detection logic
///
/// Auth and URL shape are inferred from the base URL so the user
/// only needs to fill in three fields: endpoint, key, model/deployment.
struct OpenAICompatibleImageService: Sendable {

    let baseURL: String
    let apiKey: String
    let model: String
    let authStyle: OpenAICompatibleProvider.AuthStyle

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

    func reimagine(image: CGImage,
                   prompt: String,
                   progress: @Sendable @escaping (String) -> Void = { _ in }) async throws -> CGImage {
        let (targetW, targetH, sizeLabel) = Self.bestSize(for: image)
        let host = isAzure ? "Azure OpenAI" : "OpenAI"
        progress("[\(host)] \(image.width)×\(image.height) → \(sizeLabel) · \(model)")

        let resized = resize(image, toWidth: targetW, height: targetH) ?? image
        guard let pngData = encodePNG(resized) else {
            throw ProviderError.invalidInput("Could not encode canvas as PNG")
        }

        guard let url = URL(string: editsURL) else {
            throw ProviderError.notConfigured
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        func append(_ s: String) { body.append(Data(s.utf8)) }
        func field(_ name: String, _ value: String) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"image\"; filename=\"image.png\"\r\n")
        append("Content-Type: image/png\r\n\r\n")
        body.append(pngData)
        append("\r\n")

        field("prompt", prompt)
        field("n", "1")
        field("size", sizeLabel)
        field("quality", "high")
        // OpenAI (non-Azure) needs the model in the body; Azure ignores it.
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

        progress("[\(host)] Sending request…")
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
            throw ProviderError.unknown("\(host) error: \(detail)")
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
            throw ProviderError.decodeFailure("Could not decode \(host) output image")
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
