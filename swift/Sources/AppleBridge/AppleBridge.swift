import ArgumentParser
import Foundation

@main
struct AppleBridge: AsyncParsableCommand {
    // Strip --output <path> from arguments before ArgumentParser sees them.
    // This allows any subcommand to write to a file instead of stdout,
    // needed for .app bundle mode on macOS Sequoia where stdout is not capturable.
    static func main() async {
        var args = Array(CommandLine.arguments.dropFirst())
        if let idx = args.firstIndex(of: "--output"), idx + 1 < args.count {
            JSONOutput.outputPath = args[idx + 1]
            args.remove(at: idx + 1)
            args.remove(at: idx)
        }
        do {
            var command = try Self.parseAsRoot(args)
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch {
            Self.exit(withError: error)
        }
    }

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
            MailCreateDraft.self,
            ReminderLists.self,
            RemindersCmd.self,
            RemindersToday.self,
            ReminderCreateList.self,
            ReminderCreate.self,
            ReminderComplete.self,
            ReminderDelete.self,
            ReminderDeleteList.self,
            FileList.self,
            FileInfo.self,
            FileSearchCmd.self,
            FileRead.self,
            FileMove.self,
            FileCopy.self,
            FileCreateFolder.self,
            FileTrash.self,
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

struct MailCreateDraft: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mail-create-draft",
        abstract: "Create a draft email in Mail.app."
    )

    @Option(name: .long, help: "Recipient email addresses (comma-separated)")
    var to: String

    @Option(name: .long, help: "CC email addresses (comma-separated)")
    var cc: String?

    @Option(name: .long, help: "BCC email addresses (comma-separated)")
    var bcc: String?

    @Option(name: .long, help: "Email subject")
    var subject: String

    @Option(name: .long, help: "Email body text")
    var body: String

    @Option(name: .long, help: "Sender email address (from mail-accounts)")
    var account: String?

    func run() async throws {
        let toAddrs = to.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let ccAddrs = cc?.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let bccAddrs = bcc?.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        MailBridge.createDraft(to: toAddrs, cc: ccAddrs, bcc: bccAddrs, subject: subject, body: body, account: account)
    }
}

// MARK: - Reminders Subcommands

struct ReminderLists: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reminder-lists",
        abstract: "List all reminder lists with account and color."
    )

    func run() async throws {
        await RemindersBridge.listLists()
    }
}

struct RemindersCmd: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reminders",
        abstract: "List reminders with optional filters."
    )

    @Option(name: .long, help: "Filter to a specific list name")
    var list: String?

    @Option(name: .long, help: "Filter: incomplete (default), completed, overdue, dueToday, all")
    var filter: String = "incomplete"

    @Option(name: .long, help: "Max reminders to return (default: 50)")
    var limit: Int = 50

    func run() async throws {
        await RemindersBridge.listReminders(listName: list, filter: filter, limit: limit)
    }
}

struct RemindersToday: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reminders-today",
        abstract: "Incomplete reminders due today plus overdue across all lists."
    )

    func run() async throws {
        await RemindersBridge.today()
    }
}

struct ReminderCreateList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reminder-create-list",
        abstract: "Create a new reminder list."
    )

    @Option(name: .long, help: "Name for the new list")
    var name: String

    func run() async throws {
        await RemindersBridge.createList(name: name)
    }
}

struct ReminderCreate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reminder-create",
        abstract: "Create a new reminder in a list."
    )

    @Option(name: .long, help: "List name to add the reminder to")
    var list: String

    @Option(name: .long, help: "Reminder title")
    var title: String

    @Option(name: .long, help: "Due date (ISO 8601, e.g. 2026-02-18 or 2026-02-18T10:00:00Z)")
    var due: String?

    @Option(name: .long, help: "Priority: 0=none, 1=high, 5=medium, 9=low (default: 0)")
    var priority: Int = 0

    @Option(name: .long, help: "Notes for the reminder")
    var notes: String?

    func run() async throws {
        await RemindersBridge.createReminder(listName: list, title: title, dueDate: due, priority: priority, notes: notes)
    }
}

struct ReminderComplete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reminder-complete",
        abstract: "Mark a reminder as completed."
    )

    @Option(name: .long, help: "Reminder ID (from reminders command output)")
    var id: String

    func run() async throws {
        await RemindersBridge.completeReminder(id: id)
    }
}

struct ReminderDelete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reminder-delete",
        abstract: "Delete a reminder."
    )

    @Option(name: .long, help: "Reminder ID (from reminders command output)")
    var id: String

    func run() async throws {
        await RemindersBridge.deleteReminder(id: id)
    }
}

struct ReminderDeleteList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reminder-delete-list",
        abstract: "Delete a reminder list."
    )

    @Option(name: .long, help: "List ID (from reminder-lists command output)")
    var id: String

    @Flag(name: .long, help: "Delete even if the list has reminders")
    var force: Bool = false

    func run() async throws {
        await RemindersBridge.deleteList(id: id, force: force)
    }
}

// MARK: - Files & Folders Subcommands

struct FileList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "file-list",
        abstract: "List directory contents with metadata."
    )

    @Option(name: .long, help: "Directory path (relative to ~ or absolute)")
    var path: String = "."

    @Flag(name: .long, help: "List recursively")
    var recursive: Bool = false

    @Option(name: .long, help: "Max recursion depth (default: 3)")
    var depth: Int = 3

    func run() throws {
        FilesBridge.list(path: path, recursive: recursive, depth: depth)
    }
}

struct FileInfo: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "file-info",
        abstract: "Get detailed file or folder metadata."
    )

    @Option(name: .long, help: "File path (relative to ~ or absolute)")
    var path: String

    func run() throws {
        FilesBridge.info(path: path)
    }
}

struct FileSearchCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "file-search",
        abstract: "Search files using Spotlight."
    )

    @Option(name: .long, help: "Search query (Spotlight syntax)")
    var query: String

    @Option(name: .long, help: "Filter by kind: folder, image, pdf, document, audio, video, presentation, spreadsheet")
    var kind: String?

    @Option(name: .long, help: "Search scope directory (relative to ~ or absolute)")
    var scope: String?

    func run() throws {
        FilesBridge.search(query: query, kind: kind, scope: scope)
    }
}

struct FileRead: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "file-read",
        abstract: "Read and extract text from a file."
    )

    @Option(name: .long, help: "File path (relative to ~ or absolute)")
    var path: String

    func run() throws {
        FilesBridge.read(path: path)
    }
}

struct FileMove: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "file-move",
        abstract: "Move or rename files and folders."
    )

    @Option(name: .long, help: "JSON array of {\"source\": \"...\", \"destination\": \"...\"} pairs")
    var items: String

    func run() throws {
        FilesBridge.move(itemsJSON: items)
    }
}

struct FileCopy: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "file-copy",
        abstract: "Copy a file or folder."
    )

    @Option(name: .long, help: "Source path")
    var source: String

    @Option(name: .long, help: "Destination path")
    var dest: String

    func run() throws {
        FilesBridge.copy(source: source, destination: dest)
    }
}

struct FileCreateFolder: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "file-create-folder",
        abstract: "Create a directory with intermediate directories."
    )

    @Option(name: .long, help: "Directory path to create")
    var path: String

    func run() throws {
        FilesBridge.createFolder(path: path)
    }
}

struct FileTrash: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "file-trash",
        abstract: "Move a file or folder to Trash."
    )

    @Option(name: .long, help: "File or folder path to trash")
    var path: String

    func run() throws {
        FilesBridge.trash(path: path)
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
