import Foundation

enum CanvasDebugLog {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["SEXIQL_CANVAS_DEBUG"] == "1"
    }

    static func log(_ message: String) {
        guard isEnabled else { return }
        let line = "\(Date().timeIntervalSince1970) \(message)\n"
        let url = URL(fileURLWithPath: "/tmp/sexiql-canvas-debug.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
