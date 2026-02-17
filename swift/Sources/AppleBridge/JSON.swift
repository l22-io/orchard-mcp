import Foundation

// Reason: Centralised JSON envelope so every subcommand returns a consistent
// {"status": "ok"|"error", "data": ..., "error": ...} structure.

enum JSONOutput {
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
                print(str)
            }
        } catch {
            // Reason: Last-resort fallback if JSONSerialization itself fails.
            print("{\"status\":\"error\",\"error\":\"JSON serialization failed: \(error.localizedDescription)\"}")
        }
    }
}

/// Convert a Date to ISO 8601 string in the local timezone.
func iso8601(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
}
