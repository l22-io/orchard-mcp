import ArgumentParser
import Foundation

@main
struct AppleBridge: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apple-bridge",
        abstract: "Native macOS bridge for Apple Calendar, Mail, and Reminders.",
        version: "0.1.0",
        subcommands: [
            Calendars.self,
            Events.self,
            Search.self,
            Doctor.self
        ]
    )
}

// MARK: - Calendar Subcommands

struct Calendars: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List all calendars with account info."
    )

    func run() async throws {
        await CalendarBridge.listCalendars()
    }
}

struct Events: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List events in a date range. Recurring events are expanded."
    )

    @Option(name: .long, help: "Start date (ISO 8601, e.g. 2026-02-17 or 2026-02-17T00:00:00Z)")
    var start: String

    @Option(name: .long, help: "End date (ISO 8601)")
    var end: String

    @Option(name: .long, help: "Filter by calendar ID (from 'calendars' subcommand)")
    var calendar: String?

    func run() async throws {
        await CalendarBridge.listEvents(startISO: start, endISO: end, calendarID: calendar)
    }
}

struct Search: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Search events by title, notes, or location within a date range."
    )

    @Argument(help: "Search query")
    var query: String

    @Option(name: .long, help: "Start date (ISO 8601)")
    var start: String

    @Option(name: .long, help: "End date (ISO 8601)")
    var end: String

    func run() async throws {
        await CalendarBridge.searchEvents(query: query, startISO: start, endISO: end)
    }
}

// MARK: - Doctor

struct Doctor: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check permissions and list accessible resources."
    )

    func run() async throws {
        await DoctorBridge.run()
    }
}
