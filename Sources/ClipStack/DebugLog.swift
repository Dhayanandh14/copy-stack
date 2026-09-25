import Foundation

/// Plain-file logging, shared by the capture and paste paths. The unified log
/// hides info-level messages by default, which makes it useless for answering
/// "why didn't that work".
enum DebugLog {
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "debugLogging") }

    static var url: URL {
        Store.databaseURL.deletingLastPathComponent().appendingPathComponent("debug.log")
    }

    static func write(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let line = "\(ISO8601DateFormatter().string(from: Date()))  \(message())\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}
