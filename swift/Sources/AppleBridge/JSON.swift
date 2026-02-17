import Foundation

// Reason: Centralised JSON envelope so every subcommand returns a consistent
// {"status": "ok"|"error", "data": ..., "error": ...} structure.

enum JSONOutput {
    /// When set, output is written to this file path instead of stdout.
    /// Used by .app bundle mode where stdout is not capturable.
    static var outputPath: String?

    static func success(_ data: Any) {
        let envelope: [String: Any] = [
            "status": "ok",
            "data": data
        ]
        printJSON(envelope)
    }

    static func error(_ message: String) {
        let envelope: [String: Any] = [
            "status": "error",
            "error": message
        ]
        printJSON(envelope)
    }

    private static func printJSON(_ dict: [String: Any]) {
        do {
            let data = try JSONSerialization.data(
                withJSONObject: dict,
                options: [.prettyPrinted, .sortedKeys]
            )
            if let str = String(data: data, encoding: .utf8) {
                if let path = outputPath {
                    try str.write(toFile: path, atomically: true, encoding: .utf8)
                } else {
                    print(str)
                }
            }
        } catch {
            // Reason: Last-resort fallback if JSONSerialization itself fails.
            let fallback = "{\"status\":\"error\",\"error\":\"JSON serialization failed: \(error.localizedDescription)\"}"
            if let path = outputPath {
                try? fallback.write(toFile: path, atomically: true, encoding: .utf8)
            } else {
                print(fallback)
            }
        }
    }
}

/// Convert a Date to ISO 8601 string in the local timezone.
func iso8601(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
}
