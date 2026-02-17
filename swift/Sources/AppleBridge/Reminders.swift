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

    static func listReminders(listName: String?, filter: String, limit: Int) async {
        guard await requestAccess() else {
            JSONOutput.error("Reminders access denied. Grant access in System Settings > Privacy & Security > Reminders.")
            return
        }

        var calendars: [EKCalendar]? = nil
        if let name = listName {
            let matches = store.calendars(for: .reminder).filter {
                $0.title.localizedCaseInsensitiveCompare(name) == .orderedSame
            }
            if matches.isEmpty {
                JSONOutput.error("Reminder list not found: \(name)")
                return
            }
            calendars = matches
        }

        let predicate = store.predicateForReminders(in: calendars)
        let allReminders = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { result in
                continuation.resume(returning: result ?? [])
            }
        }

        let now = Date()
        let startOfToday = Calendar.current.startOfDay(for: now)
        let endOfToday = Calendar.current.date(byAdding: .day, value: 1, to: startOfToday)!

        let filtered: [EKReminder]
        switch filter {
        case "completed":
            filtered = allReminders.filter { $0.isCompleted }
        case "overdue":
            filtered = allReminders.filter { !$0.isCompleted && $0.dueDateComponents != nil && (Calendar.current.date(from: $0.dueDateComponents!) ?? .distantFuture) < startOfToday }
        case "dueToday":
            filtered = allReminders.filter {
                guard !$0.isCompleted, let dc = $0.dueDateComponents, let due = Calendar.current.date(from: dc) else { return false }
                return due >= startOfToday && due < endOfToday
            }
        case "all":
            filtered = allReminders
        default: // "incomplete"
            filtered = allReminders.filter { !$0.isCompleted }
        }

        let limited = Array(filtered.prefix(limit))
        let result: [[String: Any]] = limited.map { rem in
            formatReminder(rem)
        }

        JSONOutput.success(result)
    }

    static func today() async {
        guard await requestAccess() else {
            JSONOutput.error("Reminders access denied. Grant access in System Settings > Privacy & Security > Reminders.")
            return
        }

        let predicate = store.predicateForReminders(in: nil)
        let allReminders = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { result in
                continuation.resume(returning: result ?? [])
            }
        }

        let now = Date()
        let startOfToday = Calendar.current.startOfDay(for: now)
        let endOfToday = Calendar.current.date(byAdding: .day, value: 1, to: startOfToday)!

        let todayAndOverdue = allReminders.filter { rem in
            guard !rem.isCompleted else { return false }
            guard let dc = rem.dueDateComponents, let due = Calendar.current.date(from: dc) else { return false }
            return due < endOfToday
        }

        let result: [[String: Any]] = todayAndOverdue.map { rem in
            formatReminder(rem)
        }

        JSONOutput.success(result)
    }

    // MARK: - Helpers

    private static func formatReminder(_ rem: EKReminder) -> [String: Any] {
        var dict: [String: Any] = [
            "title": rem.title ?? "(no title)",
            "isCompleted": rem.isCompleted,
            "list": rem.calendar.title,
            "priority": rem.priority
        ]
        if let dc = rem.dueDateComponents, let due = Calendar.current.date(from: dc) {
            dict["dueDate"] = iso8601(due)
        }
        if rem.isCompleted, let completed = rem.completionDate {
            dict["completionDate"] = iso8601(completed)
        }
        if let notes = rem.notes, !notes.isEmpty {
            dict["notes"] = notes
        }
        if rem.hasRecurrenceRules {
            dict["hasRecurrence"] = true
        }
        return dict
    }
}
