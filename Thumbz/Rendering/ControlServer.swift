import Foundation
import Network
import AppKit

/// Tiny HTTP server bound to 127.0.0.1 that exposes the document for
/// programmatic control (primarily for AI test harnesses). Zero auth — do
/// not expose beyond localhost.
///
/// Endpoints:
///   GET  /state         → JSON snapshot of document + layer tree
///   GET  /canvas.png    → PNG of the current composite
///   GET  /log/tail      → plain-text tail of the log (last 200 lines)
///   POST /action        → JSON body with {"type":"…", …}
///       types:
///         - "newDocument"
///         - "addLayer"      { "kind": "raster|text|gradient|solid" }
///         - "selectLayer"   { "id": "<uuid>" }
///         - "removeActive"
///         - "setText"       { "id": "<uuid>", "value": "..." }
///         - "setTextColor"  { "id": "<uuid>", "hex": "ff0000" }       // whole layer
///         - "setLayerOpacity" { "id":"...", "opacity": 0.5 }
///         - "toggleVisible" { "id": "..." }
///         - "moveLayer"     { "id":"...", "x":0,"y":0 }               // absolute offset
///         - "setCanvas"     { "width": 1920, "height": 1080 }
///         - "setBackground" { "hex": "0d1220" }
///         - "savePath"      { "path": "/tmp/test.thumbz" }
///         - "loadPath"      { "path": "/tmp/test.thumbz" }
///         - "exportPNG"     { "path": "/tmp/out.png" }
@MainActor
final class ControlServer {
    static let shared = ControlServer()
    private var listener: NWListener?
    private var store: DocumentStore?
    private(set) var isRunning = false
    private(set) var port: UInt16 = 0

    func start(on port: Int, store: DocumentStore) {
        if isRunning { stop() }
        self.store = store
        do {
            let params = NWParameters.tcp
            params.acceptLocalOnly = true
            let listener = try NWListener(using: params,
                                          on: NWEndpoint.Port(integerLiteral: UInt16(port)))
            listener.newConnectionHandler = { [weak self] conn in
                conn.start(queue: .main)
                Task { @MainActor in self?.receive(on: conn) }
            }
            listener.start(queue: .main)
            self.listener = listener
            self.port = UInt16(port)
            self.isRunning = true
            tlog("ControlServer: listening on 127.0.0.1:\(port)")
        } catch {
            terr("ControlServer start failed: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        tlog("ControlServer: stopped")
    }

    // MARK: - Connection handling

    private func receive(on conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, _, _ in
            guard let self, let data, !data.isEmpty else { conn.cancel(); return }
            Task { @MainActor in
                let response = self.handle(request: data)
                conn.send(content: response, completion: .contentProcessed({ _ in conn.cancel() }))
            }
        }
    }

    private func handle(request: Data) -> Data {
        guard let head = String(data: request.prefix(4096), encoding: .utf8),
              let firstLine = head.split(separator: "\r\n").first else {
            return httpResponse(status: 400, body: "Bad request")
        }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return httpResponse(status: 400, body: "Bad request") }
        let method = String(parts[0])
        let pathRaw = String(parts[1])
        let path = pathRaw.split(separator: "?").first.map(String.init) ?? pathRaw

        switch (method, path) {
        case ("GET", "/state"):         return handleState()
        case ("GET", "/canvas.png"):    return handleCanvasPNG()
        case ("GET", "/log/tail"):      return handleLogTail()
        case ("GET", "/"):              return httpResponse(status: 200, body: "Thumbz Control Server. See /state, /canvas.png, /action")
        case ("POST", "/action"):       return handleAction(request: request)
        default:
            return httpResponse(status: 404, body: "Not found: \(method) \(path)")
        }
    }

    // MARK: - Handlers

    private func handleState() -> Data {
        guard let store else { return httpResponse(status: 503, body: "No store") }
        let snap: [String: Any] = [
            "canvas": ["width": Int(store.canvasSize.width), "height": Int(store.canvasSize.height)],
            "background": hex(store.backgroundColor),
            "activeLayerID": store.activeLayerID?.uuidString ?? NSNull(),
            "isDirty": store.isDirty,
            "currentFile": store.currentFileURL?.path ?? NSNull(),
            "layers": store.layers.map { L -> [String: Any] in
                [
                    "id": L.id.uuidString,
                    "name": L.name,
                    "kind": L.kind.rawValue,
                    "visible": L.visible,
                    "opacity": L.opacity,
                    "blend": L.blend.rawValue,
                    "offsetX": L.offset.width,
                    "offsetY": L.offset.height,
                    "textString": L.kind == .text ? L.text.string : NSNull()
                ]
            }
        ]
        return jsonResponse(snap)
    }

    private func handleCanvasPNG() -> Data {
        guard let store else { return httpResponse(status: 503, body: "No store") }
        guard let cg = LayerRenderer.composite(store: store) else {
            return httpResponse(status: 500, body: "Composite failed")
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            return httpResponse(status: 500, body: "Encode failed")
        }
        return httpResponse(status: 200, contentType: "image/png", bodyData: png)
    }

    private func handleLogTail() -> Data {
        let entries = Log.console.entries.suffix(200)
        let text = entries.map { "\(ISO8601DateFormatter().string(from: $0.date)) [\($0.level)] \($0.message)" }.joined(separator: "\n")
        return httpResponse(status: 200, contentType: "text/plain", body: text)
    }

    private func handleAction(request: Data) -> Data {
        guard let store else { return httpResponse(status: 503, body: "No store") }
        // Parse body — very naive split on \r\n\r\n
        let sep = Data([0x0d, 0x0a, 0x0d, 0x0a])
        guard let range = request.range(of: sep) else { return httpResponse(status: 400, body: "No body") }
        let body = request.subdata(in: range.upperBound..<request.endIndex)
        guard let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let type = obj["type"] as? String else {
            return httpResponse(status: 400, body: "Bad JSON")
        }

        func layer(_ id: String) -> PXLayer? {
            store.layers.first(where: { $0.id.uuidString == id })
        }

        switch type {
        case "newDocument":
            store.layers.removeAll(); store.currentFileURL = nil; store.isDirty = false; store.invalidate()
        case "addLayer":
            let kind = (obj["kind"] as? String).flatMap(LayerKind.init(rawValue:)) ?? .raster
            let L = PXLayer(name: kind.rawValue.capitalized, kind: kind)
            store.addLayer(L)
            return jsonResponse(["ok": true, "id": L.id.uuidString])
        case "selectLayer":
            if let id = obj["id"] as? String { store.activeLayerID = UUID(uuidString: id) }
        case "removeActive":
            store.removeActive()
        case "setText":
            if let id = obj["id"] as? String, let v = obj["value"] as? String, let L = layer(id), L.kind == .text {
                L.text.string = v
                L.text.rtfData = nil
                store.invalidate()
            }
        case "setTextColor":
            if let id = obj["id"] as? String, let hex = obj["hex"] as? String,
               let L = layer(id), L.kind == .text, let nsc = NSColor.fromHex(hex) {
                L.text.color = ColorRGB(nsc)
                L.text.rtfData = nil
                store.invalidate()
            }
        case "setLayerOpacity":
            if let id = obj["id"] as? String, let o = obj["opacity"] as? Double, let L = layer(id) {
                L.opacity = o; store.invalidate()
            }
        case "toggleVisible":
            if let id = obj["id"] as? String, let L = layer(id) { L.visible.toggle(); store.invalidate() }
        case "moveLayer":
            if let id = obj["id"] as? String, let L = layer(id) {
                L.offset = CGSize(width: obj["x"] as? Double ?? 0, height: obj["y"] as? Double ?? 0)
                store.invalidate()
            }
        case "setCanvas":
            if let w = obj["width"] as? Double, let h = obj["height"] as? Double {
                store.canvasSize = CGSize(width: w, height: h); store.invalidate()
            }
        case "setBackground":
            if let hex = obj["hex"] as? String, let nsc = NSColor.fromHex(hex) {
                store.backgroundColor = ColorRGB(nsc); store.invalidate()
            }
        case "savePath":
            if let path = obj["path"] as? String {
                let url = URL(fileURLWithPath: path)
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                if let data = try? encoder.encode(store.makeSnapshot()) {
                    try? data.write(to: url, options: .atomic)
                    store.currentFileURL = url; store.isDirty = false
                }
            }
        case "loadPath":
            if let path = obj["path"] as? String,
               let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let snap = try? JSONDecoder().decode(DocumentSnapshot.self, from: data) {
                store.apply(snap)
                store.currentFileURL = URL(fileURLWithPath: path)
            }
        case "exportPNG":
            if let path = obj["path"] as? String,
               let cg = LayerRenderer.composite(store: store) {
                let rep = NSBitmapImageRep(cgImage: cg)
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: path))
                }
            }
        default:
            return httpResponse(status: 400, body: "Unknown action type: \(type)")
        }
        return jsonResponse(["ok": true])
    }

    // MARK: - HTTP plumbing

    private func jsonResponse(_ obj: Any) -> Data {
        let data = (try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]))
            ?? Data("{}".utf8)
        return httpResponse(status: 200, contentType: "application/json", bodyData: data)
    }

    private func httpResponse(status: Int, contentType: String = "text/plain; charset=utf-8",
                               body: String = "") -> Data {
        httpResponse(status: status, contentType: contentType, bodyData: Data(body.utf8))
    }

    private func httpResponse(status: Int, contentType: String = "text/plain; charset=utf-8",
                               bodyData: Data) -> Data {
        let reason: String = [200: "OK", 400: "Bad Request", 404: "Not Found",
                              500: "Internal Server Error", 503: "Service Unavailable"][status] ?? "OK"
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(bodyData.count)\r\n"
        head += "Access-Control-Allow-Origin: *\r\n"
        head += "Connection: close\r\n\r\n"
        var data = Data(head.utf8)
        data.append(bodyData)
        return data
    }

    private func hex(_ c: ColorRGB) -> String {
        String(format: "#%02x%02x%02x",
               Int((c.r * 255).rounded()),
               Int((c.g * 255).rounded()),
               Int((c.b * 255).rounded()))
    }
}
