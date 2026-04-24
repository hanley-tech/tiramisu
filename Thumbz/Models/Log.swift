import Foundation
import Observation
import AppKit

/// Ship-grade logger: writes to `~/Library/Logs/Thumbz/Thumbz.log` and mirrors to an
/// in-app console (LogConsole). Call `tlog("…")` from anywhere.
final class Log: @unchecked Sendable {
    static let shared = Log()
    @MainActor static let console = LogConsole()

    let fileURL: URL
    private let queue = DispatchQueue(label: "ai.taiso.thumbz.log")
    private static let fmt: @Sendable () -> ISO8601DateFormatter = {
        // ISO8601DateFormatter is thread-safe per Apple docs but not typed Sendable.
        // Keep a per-thread instance to sidestep the Swift 6 complaint.
        { () -> ISO8601DateFormatter in
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f
        }
    }()

    private init() {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Logs/Thumbz", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("Thumbz.log")
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        log("info", "— Log session start —")
    }

    func log(_ level: String, _ message: String) {
        let date = Date()
        let line = "\(Self.fmt().string(from: date)) [\(level)] \(message)\n"
        queue.async { [fileURL] in
            if let data = line.data(using: .utf8) {
                if let fh = try? FileHandle(forWritingTo: fileURL) {
                    try? fh.seekToEnd()
                    try? fh.write(contentsOf: data)
                    try? fh.close()
                }
            }
        }
        Task { @MainActor in
            Log.console.append(Entry(id: UUID(), date: date, level: level, message: message))
        }
        FileHandle.standardError.write(line.data(using: .utf8) ?? Data())
    }

    func reveal() {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }
}

struct Entry: Identifiable, Sendable {
    let id: UUID
    let date: Date
    let level: String
    let message: String
}

@Observable
@MainActor
final class LogConsole {
    var entries: [Entry] = []
    let maxEntries = 2000
    func append(_ e: Entry) {
        entries.append(e)
        if entries.count > maxEntries { entries.removeFirst(entries.count - maxEntries) }
    }
    func clear() { entries.removeAll() }
}

// Convenience top-level functions
func tlog(_ message: String) { Log.shared.log("info", message) }
func twarn(_ message: String) { Log.shared.log("warn", message) }
func terr(_ message: String) { Log.shared.log("error", message) }
