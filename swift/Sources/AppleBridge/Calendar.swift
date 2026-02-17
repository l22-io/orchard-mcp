import EventKit
import Foundation

// Reason: All calendar access goes through EventKit, which properly handles
// recurring event expansion via predicateForEvents -- something AppleScript cannot do.

enum CalendarBridge {
    private static let store = EKEventStore()

    /// Request full calendar access. Returns true if granted.
    static func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToEvents()
        } catch {
            return false
        }
    }

    /// Check current authorization status without prompting.
    static func authorizationStatus() -> EKAuthorizationStatus {
        return EKEventStore.authorizationStatus(for: .event)
    }

    /// List all calendars with account and metadata.
    static func listCalendars() async {
        guard await requestAccess() else {
            JSONOutput.error("Calendar access denied. Grant access in System Settings > Privacy & Security > Calendars.")
            return
        }

        let calendars = store.calendars(for: .event)
        let result: [[String: Any]] = calendars.map { cal in
            var dict: [String: Any] = [
                "id": cal.calendarIdentifier,
                "title": cal.title,
                "type": calendarTypeName(cal.type),
                "allowsModify": cal.allowsContentModifications
            ]
            if let source = cal.source {
                dict["account"] = source.title
                dict["accountType"] = sourceTypeName(source.sourceType)
            }
            if let color = cal.cgColor {
                // Reason: Convert CGColor to hex for easy display/filtering.
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

    /// Fetch events in a date range, optionally filtered by calendar ID.
    /// Recurring events are properly expanded via predicateForEvents.
    static func listEvents(startISO: String, endISO: String, calendarID: String?) async {
        guard await requestAccess() else {
            JSONOutput.error("Calendar access denied.")
            return
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        guard let startDate = formatter.date(from: startISO) ?? parseFlexibleISO(startISO) else {
            JSONOutput.error("Invalid start date: \(startISO). Use ISO 8601 format.")
            return
        }
        guard let endDate = formatter.date(from: endISO) ?? parseFlexibleISO(endISO) else {
            JSONOutput.error("Invalid end date: \(endISO). Use ISO 8601 format.")
            return
        }

        var calendars: [EKCalendar]? = nil
        if let calID = calendarID {
            if let cal = store.calendar(withIdentifier: calID) {
                calendars = [cal]
            } else {
                JSONOutput.error("Calendar not found: \(calID)")
                return
            }
        }

        let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
        let events = store.events(matching: predicate)

        let result: [[String: Any]] = events.map { evt in
            var dict: [String: Any] = [
                "id": evt.eventIdentifier ?? "",
                "title": evt.title ?? "(no title)",
                "start": iso8601(evt.startDate),
                "end": iso8601(evt.endDate),
                "isAllDay": evt.isAllDay,
                "calendar": evt.calendar.title,
                "calendarId": evt.calendar.calendarIdentifier
            ]
            if let location = evt.location, !location.isEmpty {
                dict["location"] = location
            }
            if let notes = evt.notes, !notes.isEmpty {
                dict["notes"] = notes
            }
            if let url = evt.url {
                dict["url"] = url.absoluteString
            }
            if evt.hasRecurrenceRules {
                dict["isRecurring"] = true
            }
            if let attendees = evt.attendees, !attendees.isEmpty {
                dict["attendees"] = attendees.map { a in
                    var info: [String: Any] = [
                        "name": a.name ?? a.url.absoluteString,
                        "status": participantStatusName(a.participantStatus)
                    ]
                    if a.isCurrentUser {
                        info["isMe"] = true
                    }
                    return info
                }
            }
            return dict
        }

        JSONOutput.success(result)
    }

    /// Search events by title within a date range.
    static func searchEvents(query: String, startISO: String, endISO: String) async {
        guard await requestAccess() else {
            JSONOutput.error("Calendar access denied.")
            return
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        guard let startDate = formatter.date(from: startISO) ?? parseFlexibleISO(startISO) else {
            JSONOutput.error("Invalid start date: \(startISO)")
            return
        }
        guard let endDate = formatter.date(from: endISO) ?? parseFlexibleISO(endISO) else {
            JSONOutput.error("Invalid end date: \(endISO)")
            return
        }

        let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let events = store.events(matching: predicate)

        let lowered = query.lowercased()
        let filtered = events.filter { evt in
            let title = (evt.title ?? "").lowercased()
            let notes = (evt.notes ?? "").lowercased()
            let location = (evt.location ?? "").lowercased()
            return title.contains(lowered) || notes.contains(lowered) || location.contains(lowered)
        }

        let result: [[String: Any]] = filtered.map { evt in
            [
                "id": evt.eventIdentifier ?? "",
                "title": evt.title ?? "(no title)",
                "start": iso8601(evt.startDate),
                "end": iso8601(evt.endDate),
                "isAllDay": evt.isAllDay,
                "calendar": evt.calendar.title
            ]
        }

        JSONOutput.success(result)
    }

    // MARK: - Helpers

    private static func parseFlexibleISO(_ str: String) -> Date? {
        // Reason: Accept date-only strings like "2026-02-17" without time component.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: str)
    }

    private static func calendarTypeName(_ type: EKCalendarType) -> String {
        switch type {
        case .local: return "local"
        case .calDAV: return "caldav"
        case .exchange: return "exchange"
        case .subscription: return "subscription"
        case .birthday: return "birthday"
        @unknown default: return "unknown"
        }
    }

    private static func sourceTypeName(_ type: EKSourceType) -> String {
        switch type {
        case .local: return "local"
        case .exchange: return "exchange"
        case .calDAV: return "caldav"
        case .mobileMe: return "mobileme"
        case .subscribed: return "subscribed"
        case .birthdays: return "birthdays"
        @unknown default: return "unknown"
        }
    }

    private static func participantStatusName(_ status: EKParticipantStatus) -> String {
        switch status {
        case .unknown: return "unknown"
        case .pending: return "pending"
        case .accepted: return "accepted"
        case .declined: return "declined"
        case .tentative: return "tentative"
        case .delegated: return "delegated"
        case .completed: return "completed"
        case .inProcess: return "in_process"
        @unknown default: return "unknown"
        }
    }
}
