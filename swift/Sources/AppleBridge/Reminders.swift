import EventKit
import Foundation

enum RemindersBridge {
    private static let store = EKEventStore()

    static func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToReminders()
        } catch {
            return false
        }
    }

    static func authorizationStatus() -> EKAuthorizationStatus {
        return EKEventStore.authorizationStatus(for: .reminder)
    }

    static func listLists() async {
        guard await requestAccess() else {
            JSONOutput.error("Reminders access denied. Grant access in System Settings > Privacy & Security > Reminders.")
            return
        }

        let calendars = store.calendars(for: .reminder)

        // Fetch all reminders to count per list
        let predicate = store.predicateForReminders(in: nil)
        let allReminders = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { result in
                continuation.resume(returning: result ?? [])
            }
        }

        // Count reminders per calendar
        var counts: [String: Int] = [:]
        for rem in allReminders {
            let calId = rem.calendar.calendarIdentifier
            counts[calId, default: 0] += 1
        }

        let result: [[String: Any]] = calendars.map { cal in
            var dict: [String: Any] = [
                "id": cal.calendarIdentifier,
                "title": cal.title,
                "allowsModify": cal.allowsContentModifications,
                "itemCount": counts[cal.calendarIdentifier] ?? 0
            ]
            if let source = cal.source {
                dict["account"] = source.title
            }
            if let color = cal.cgColor {
                let components = color.components ?? []
                if components.count >= 3 {
                    let r = Int(components[0] * 255)
                    let g = Int(components[1] * 255)
                    let b = Int(components[2] * 255)
                    dict["color"] = String(format: "#%02x%02x%02x", r, g, b)
                }
            }
            return dict
        }

        JSONOutput.success(result)
    }
}
