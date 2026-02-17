import ArgumentParser
import Foundation

@main
struct AppleBridge: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apple-bridge",
        abstract: "Native macOS bridge for Apple Calendar, Mail, and Reminders.",
        version: "0.2.0",
        subcommands: [
            Calendars.self,
            Events.self,
            Search.self,
            MailAccounts.self,
            MailUnread.self,
            MailSearchCmd.self,
            MailMessage.self,
            MailFlagged.self,
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

// MARK: - Mail Subcommands

struct MailAccounts: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mail-accounts",
        abstract: "List all mail accounts with mailboxes and unread counts."
    )

    func run() async throws {
        MailBridge.listAccounts()
    }
}

struct MailUnread: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mail-unread",
        abstract: "Unread summary per account with recent message subjects."
    )

    @Option(name: .long, help: "Max unread messages to return per account (default: 10)")
    var limit: Int = 10

    func run() async throws {
        MailBridge.unreadSummary(limit: limit)
    }
}

struct MailSearchCmd: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mail-search",
        abstract: "Search messages by subject or sender."
    )

    @Option(name: .long, help: "Search query (matches subject and sender)")
    var query: String

    @Option(name: .long, help: "Filter to specific account name")
    var account: String?

    @Option(name: .long, help: "Mailbox to search in (default: inbox)")
    var mailbox: String?

    @Option(name: .long, help: "Max results to return (default: 20)")
    var limit: Int = 20

    func run() async throws {
        MailBridge.search(query: query, account: account, mailbox: mailbox, limit: limit)
    }
}

struct MailMessage: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mail-message",
        abstract: "Get full message content by message ID."
    )

    @Option(name: .long, help: "Message ID (from mail-search or mail-unread)")
    var id: String

    func run() async throws {
        MailBridge.readMessage(messageId: id)
    }
}

struct MailFlagged: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mail-flagged",
        abstract: "List flagged messages across all accounts."
    )

    @Option(name: .long, help: "Max results to return (default: 20)")
    var limit: Int = 20

    func run() async throws {
        MailBridge.flagged(limit: limit)
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
