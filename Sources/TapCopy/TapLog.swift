import Foundation

/// Lightweight, rotation-capped diagnostic log at ~/Library/Logs/TapCopy.log.
/// Used by support to trace the selection pipeline without opening Xcode.
enum TapLog {

    private static let queue = DispatchQueue(label: "com.blackeye.tapcopy.log")
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private static let fileURL: URL = {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("TapCopy.log")
    }()

    static func log(_ message: String) {
        NSLog("TapCopy: %@", message)
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        queue.async {
            let path = fileURL.path
            if let attributes = try? FileManager.default.attributesOfItem(atPath: path),
               let size = attributes[.size] as? UInt64, size > 512 * 1024 {
                try? FileManager.default.removeItem(atPath: path)
            }
            if !FileManager.default.fileExists(atPath: path) {
                try? line.write(to: fileURL, atomically: true, encoding: .utf8)
                return
            }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                try? handle.seekToEnd()
                try? handle.write(contentsOf: Data(line.utf8))
            }
        }
    }
}
