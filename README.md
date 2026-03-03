# orchard-mcp

![Orchard MCP](docs/banner.jpg)

MCP server for Apple Calendar, Mail, Reminders, and Files on macOS using native frameworks.

Gives any MCP-compatible client (Warp, Claude Desktop, Claude Code, Cursor) structured
access to your local Apple Calendar, Apple Mail, Apple Reminders, and filesystem through
native macOS frameworks. No cloud dependencies, no OAuth setup -- all data stays local.

## How it works

orchard-mcp reads from the local macOS data stores (EventKit for Calendar/Reminders,
AppleScript for Mail) which are already populated by accounts configured in
**System Settings > Internet Accounts**. The OS handles all authentication with Google,
Microsoft, iCloud, etc. natively. orchard-mcp never communicates with any remote service
and requires no OAuth client IDs, redirect URIs, or token management.

**Privacy note:** orchard-mcp itself sends no data anywhere. However, the MCP client
(e.g. Claude, Cursor) that invokes tools will receive the returned data (calendar events,
emails, reminders, file contents) and send it to its LLM provider as part of the
conversation context. Be mindful of what you ask the LLM to access.

The only permissions needed are macOS TCC grants (e.g. "Allow access to Calendars"),
triggered automatically on first run.

## Status

- Phase 1 (Calendar + System) -- complete
- Phase 2 (Reminders read + write) -- complete
- Phase 3 (Mail read + create_draft) -- complete
- Phase 4a (Setup Wizard) -- complete
- Phase 4b (Distribution) -- complete

See `docs/PRD.md` for the full roadmap.

## Requirements

- macOS 14+ (Sonoma or later)
- Node.js 18+

## Install

```bash
npm install -g @l22-io/orchard-mcp
orchard-mcp setup
```

No Swift or Xcode required -- the npm package ships a prebuilt universal binary (arm64 + x86_64).

The setup wizard verifies prerequisites, triggers macOS permission prompts, and generates
MCP client configuration.

### From source (development)

See [CONTRIBUTING.md](CONTRIBUTING.md) for building from source.

## MCP Client Configuration

### Warp

Add as an MCP server in Warp settings with:
```json
{"command": "npx", "args": ["@l22-io/orchard-mcp"]}
```

### Claude Desktop

Edit `~/Library/Application Support/Claude/claude_desktop_config.json`:
```json
{
  "mcpServers": {
    "orchard": {
      "command": "npx",
      "args": ["@l22-io/orchard-mcp"]
    }
  }
}
```

### Claude Code

```bash
claude mcp add --scope user orchard -- npx @l22-io/orchard-mcp
```

### Cursor

Add to your MCP settings:
```json
{"command": "npx", "args": ["@l22-io/orchard-mcp"]}
```

## Available Tools

### Calendar

- `calendar.list_calendars` -- List all calendars with account, type, color
- `calendar.list_events` -- Events in a date range (recurring events expanded)
- `calendar.today` -- Today's events across all calendars
- `calendar.search` -- Search events by title/notes/location

### Mail

- `mail.list_accounts` -- List all mail accounts with mailboxes and unread counts
- `mail.unread_summary` -- Unread count per account with recent message headers
- `mail.search` -- Search messages by subject/sender across accounts
- `mail.read_message` -- Get full message content by message ID
- `mail.flagged` -- List flagged messages across all accounts
- `mail.create_draft` -- Create a draft email (opens compose window for review)
- `mail.save_attachment` -- Save an email attachment to disk by message ID and index

### Reminders

- `reminders.list_lists` -- List all reminder lists with account, color, item count
- `reminders.list_reminders` -- Reminders from a list with filters (incomplete, completed, overdue, dueToday)
- `reminders.today` -- Incomplete reminders due today + overdue across all lists
- `reminders.create_list` -- Create a new reminder list
- `reminders.create_reminder` -- Create a reminder with optional due date, priority, notes
- `reminders.complete_reminder` -- Mark a reminder as completed
- `reminders.delete_reminder` -- Delete a reminder
- `reminders.delete_list` -- Delete a reminder list

### Files

- `files.list` -- List directory contents with metadata
- `files.info` -- Get detailed file metadata including Spotlight attributes
- `files.search` -- Search files using macOS Spotlight
- `files.read` -- Read/extract text from files (plain text, PDF, images via OCR, .docx/.rtf/.pages)
- `files.move` -- Move or rename files and folders (supports batch operations)
- `files.copy` -- Copy a file or folder
- `files.create_folder` -- Create a new directory
- `files.trash` -- Move a file or folder to Trash (reversible)

### System

- `system.doctor` -- Check permissions, list accessible accounts

## Architecture

Two-layer design:

1. **TypeScript MCP server** (`src/`) -- handles MCP protocol via stdio, Zod schemas, tool routing
2. **Swift CLI** (`swift/`) -- native binary (`apple-bridge`) using EventKit for Calendar/Reminders, AppleScript for Mail

The TypeScript layer calls the Swift binary via `child_process.execFile` and parses
JSON responses. All subcommands return a `{"status": "ok"|"error", "data": ..., "error": ...}` envelope.

### Swift CLI subcommands

```
apple-bridge calendars              List all calendars
apple-bridge events                 Events in a date range (--start, --end, --calendar)
apple-bridge search                 Search events by text (--start, --end)
apple-bridge reminder-lists          List all reminder lists
apple-bridge reminders               Reminders with filters (--list, --filter, --limit)
apple-bridge reminders-today         Due today + overdue reminders
apple-bridge reminder-create-list    Create a new reminder list (--name)
apple-bridge reminder-create         Create a reminder (--list, --title, --due, --priority, --notes)
apple-bridge reminder-complete       Mark a reminder as completed (--id)
apple-bridge reminder-delete         Delete a reminder (--id)
apple-bridge reminder-delete-list    Delete a reminder list (--id, --force)
apple-bridge mail-accounts           List mail accounts and mailboxes
apple-bridge mail-unread             Unread summary per account (--limit)
apple-bridge mail-search             Search messages (--query, --account, --mailbox, --limit)
apple-bridge mail-message            Full message content (--id)
apple-bridge mail-flagged            Flagged messages (--limit)
apple-bridge mail-create-draft       Create a draft email (--to, --subject, --body, --cc, --bcc, --account)
apple-bridge doctor                  Check permissions and accessible resources
```

## Environment Variables

- `APPLE_BRIDGE_BIN` -- Override path to the Swift binary

## License

MIT
