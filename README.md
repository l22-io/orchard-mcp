# orchard-mcp

![Orchard MCP](docs/banner.jpg)

MCP server for local macOS apps and files using native frameworks.

Gives any MCP-compatible client (Warp, Claude Desktop, Claude Code, Cursor) structured
access to Apple Calendar, Mail, Reminders, Notes, Contacts, Files, Numbers, Pages, and
Keynote. There are no cloud dependencies and no OAuth setup: data comes from the local
macOS stores and apps already configured on your machine.

## How it works

orchard-mcp reads from local macOS data stores and apps:

- EventKit for Calendar and Reminders
- Contacts.framework for Contacts
- FileManager, Spotlight, PDFKit, and Vision for files and text extraction
- AppleScript/JXA for Mail, Notes, Numbers, Pages, and Keynote

The OS handles account authentication through **System Settings > Internet Accounts**.
orchard-mcp itself never communicates with any remote service and requires no OAuth
client IDs, redirect URIs, or token management.

**Privacy note:** orchard-mcp itself sends no data anywhere. However, the MCP client
that invokes tools receives the returned data (calendar events, emails, reminders,
files, notes, contacts, and documents) as part of the conversation context. Be mindful
of what you ask the client to access.

## App Safety

orchard-mcp refuses broad requests rather than making host apps unresponsive. Mail.app,
Notes, Numbers, Pages, and Keynote calls are serialized through app-specific safety
lanes with timeout, queue, and output-size budgets. Expensive scopes are rejected before
AppleScript/JXA starts.

Examples:

- `mail.save_attachment` requires `account` and `mailbox` from a recent Mail result.
- Notes body/all search is refused; use title search, then `notes.read_note`.
- `numbers.read` and `numbers.get_formulas` require a cell range.
- PNG/JPEG Keynote export requires a single slide index.
- Calendar list/search ranges are capped at 31 days.

See [docs/app-safety-audit.md](docs/app-safety-audit.md) for the current audit and
guardrails.

The only permissions needed are macOS TCC grants (for example, "Allow access to
Calendars"), triggered automatically on first use or during setup.

## Status

Current release: 66 tools across Calendar, Mail, Reminders, Files, System, Numbers,
Pages, Keynote, Notes, and Contacts. See [CHANGELOG.md](CHANGELOG.md) for release
history.

## Requirements

- macOS 14+ (Sonoma or later)
- Node.js 22+

## Install

```bash
npm install -g @l22-io/orchard-mcp
orchard-mcp setup
```

If Xcode Command Line Tools are installed (`xcode-select --install`), `postinstall` builds
`apple-bridge` from source - the strongest install-time guarantee. Otherwise the package
falls back to the shipped prebuilt universal binary (arm64 + x86_64) and verifies its
SHA-256 against the manifest published inside the tarball.

The setup wizard verifies prerequisites, triggers macOS permission prompts, and generates
MCP client configuration.

### From Source

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

## Configuration

By default, orchard-mcp exposes all 66 tools. You can restrict which modules are enabled
and optionally limit how far back calendar events and completed reminders are returned.

### Config file

Create `~/.config/orchard-mcp/config.json`:

```json
{
  "modules": ["calendar", "reminders", "files", "system"],
  "calendarMaxAgeDays": 365,
  "remindersMaxAgeDays": 90
}
```

Override the file path with `ORCHARD_MCP_CONFIG`.

If the file omits `modules`, all modules remain enabled. Disabled modules are not
registered with MCP, so their tools cannot be listed or called.

Age limits are optional:

- **Calendar** (`list_events`, `today`, `search`): events whose `end` is before the
  cutoff are omitted.
- **Reminders** (`list_reminders`, `today`): completed reminders whose `completionDate`
  is before the cutoff are omitted. Incomplete reminders (including overdue items) are
  always returned.

### Environment variables

Set these in your MCP client's `"env"` block (they override the config file):

| Variable | Purpose |
|----------|---------|
| `ORCHARD_MCP_CONFIG` | Custom config file path |
| `ORCHARD_MCP_MODULES` | Comma-separated module list (e.g. `calendar,mail,files`) |
| `ORCHARD_MCP_CALENDAR_MAX_AGE_DAYS` | Non-negative integer; unset = no limit |
| `ORCHARD_MCP_REMINDERS_MAX_AGE_DAYS` | Non-negative integer; unset = no limit |

Example for Claude Desktop or Cursor:

```json
{
  "mcpServers": {
    "orchard": {
      "command": "npx",
      "args": ["@l22-io/orchard-mcp"],
      "env": {
        "ORCHARD_MCP_MODULES": "calendar,reminders,files,system"
      }
    }
  }
}
```

Valid module names: `calendar`, `mail`, `reminders`, `files`, `system`, `numbers`,
`pages`, `keynote`, `notes`, `contacts`.

## Available Tools

### Calendar

- `calendar.list_calendars` - List all calendars with account, type, color
- `calendar.list_events` - Events in a date range (recurring events expanded)
- `calendar.today` - Today's events across all calendars
- `calendar.search` - Search events by title, notes, or location
- `calendar.create_event` - Create a new calendar event

### Mail

- `mail.list_accounts` - List mail accounts with a bounded mailbox-name sample; use `mail.unread_summary` for unread counts
- `mail.unread_summary` - Unread count per account with recent message headers
- `mail.search` - Search messages by subject, sender, body, or all fields with pagination
- `mail.read_message` - Get message content by ID with configurable body truncation; pass account/mailbox locators when available
- `mail.flagged` - List flagged messages across all accounts with pagination
- `mail.create_draft` - Create a draft email in Mail.app for review
- `mail.save_attachment` - Save an email attachment to disk by message ID, index, account, and mailbox

### Reminders

- `reminders.list_lists` - List all reminder lists with account, color, item count
- `reminders.list_reminders` - Reminders from a list with filters
- `reminders.today` - Incomplete reminders due today plus overdue reminders
- `reminders.create_list` - Create a new reminder list
- `reminders.create_reminder` - Create a reminder with optional due date, priority, notes
- `reminders.complete_reminder` - Mark a reminder as completed
- `reminders.delete_reminder` - Delete a reminder
- `reminders.delete_list` - Delete a reminder list

### Files

- `files.list` - List directory contents with metadata
- `files.info` - Get detailed file metadata including Spotlight attributes
- `files.search` - Search files using macOS Spotlight
- `files.read` - Read or extract text from plain text, PDF, images, `.docx`, `.rtf`, `.pages`
- `files.move` - Move or rename files and folders, including batch operations
- `files.copy` - Copy a file or folder
- `files.create_folder` - Create a new directory
- `files.trash` - Move a file or folder to Trash

### System

- `system.doctor` - Check permissions and list accessible accounts/apps

### Numbers

- `numbers.search` - Find Numbers spreadsheets with Spotlight
- `numbers.read` - Read table data from a spreadsheet within a required cell range
- `numbers.write` - Write table data to a spreadsheet
- `numbers.create` - Create a new spreadsheet
- `numbers.list_sheets` - List sheets and tables
- `numbers.add_sheet` - Add a sheet
- `numbers.remove_sheet` - Remove a sheet
- `numbers.get_formulas` - Read formulas within a required cell range
- `numbers.export` - Export as CSV, PDF, or XLSX
- `numbers.info` - Inspect spreadsheet metadata

### Pages

- `pages.search` - Find Pages documents with Spotlight
- `pages.read` - Read document text
- `pages.write` - Replace document text
- `pages.create` - Create a new document
- `pages.find_replace` - Find and replace text
- `pages.insert_table` - Insert table data
- `pages.list_sections` - List document sections
- `pages.export` - Export as PDF, DOCX, TXT, or EPUB
- `pages.info` - Inspect document metadata

### Keynote

- `keynote.search` - Find Keynote decks with Spotlight
- `keynote.read` - Read slide content
- `keynote.create` - Create a new deck
- `keynote.add_slide` - Add a slide
- `keynote.edit_slide` - Edit slide title, body, or notes
- `keynote.remove_slide` - Remove a slide
- `keynote.reorder_slides` - Move slides
- `keynote.list_slides` - List slides
- `keynote.list_themes` - List available themes
- `keynote.export` - Export as PDF, PPTX, PNG, or JPEG; PNG/JPEG requires a slide index
- `keynote.info` - Inspect deck metadata

### Notes

- `notes.list_folders` - List Notes folders
- `notes.list_notes` - List notes with optional folder filtering
- `notes.search` - Search notes by title; body/all search is refused for app safety
- `notes.read_note` - Read a note by ID

### Contacts

- `contacts.list_groups` - List contact groups
- `contacts.search` - Search contacts
- `contacts.read_contact` - Read full contact details by ID

## Architecture

Two-layer design:

1. **TypeScript MCP server** (`src/`) - handles MCP protocol over stdio, Zod schemas, and tool routing
2. **Swift CLI** (`swift/`) - native binary (`apple-bridge`) using macOS frameworks and app automation

The TypeScript layer spawns the Swift binary with `child_process.spawn` and parses JSON
responses. All subcommands return a `{"status": "ok"|"error", "data": ..., "error": ...}`
envelope.

`apple-bridge` normally runs from `swift/.build/AppleBridge.app` so macOS TCC grants are
attached to the app bundle. Direct binary execution is still available through
`APPLE_BRIDGE_BIN` for trusted custom installations.

### Swift CLI Subcommands

```text
apple-bridge calendars
apple-bridge events
apple-bridge search
apple-bridge event-create
apple-bridge mail-accounts
apple-bridge mail-unread
apple-bridge mail-search
apple-bridge mail-message
apple-bridge mail-flagged
apple-bridge mail-create-draft
apple-bridge mail-save-attachment
apple-bridge reminder-lists
apple-bridge reminders
apple-bridge reminders-today
apple-bridge reminder-create-list
apple-bridge reminder-create
apple-bridge reminder-complete
apple-bridge reminder-delete
apple-bridge reminder-delete-list
apple-bridge file-list
apple-bridge file-info
apple-bridge file-search
apple-bridge file-read
apple-bridge file-move
apple-bridge file-copy
apple-bridge file-create-folder
apple-bridge file-trash
apple-bridge doctor
apple-bridge numbers-search
apple-bridge numbers-read
apple-bridge numbers-write
apple-bridge numbers-create
apple-bridge numbers-list-sheets
apple-bridge numbers-add-sheet
apple-bridge numbers-remove-sheet
apple-bridge numbers-get-formulas
apple-bridge numbers-export
apple-bridge numbers-info
apple-bridge pages-search
apple-bridge pages-read
apple-bridge pages-write
apple-bridge pages-create
apple-bridge pages-find-replace
apple-bridge pages-insert-table
apple-bridge pages-list-sections
apple-bridge pages-export
apple-bridge pages-info
apple-bridge keynote-search
apple-bridge keynote-read
apple-bridge keynote-create
apple-bridge keynote-add-slide
apple-bridge keynote-edit-slide
apple-bridge keynote-remove-slide
apple-bridge keynote-reorder-slides
apple-bridge keynote-list-slides
apple-bridge keynote-list-themes
apple-bridge keynote-export
apple-bridge keynote-info
apple-bridge notes-folders
apple-bridge notes-list
apple-bridge notes-search
apple-bridge notes-read
apple-bridge contacts-groups
apple-bridge contacts-search
apple-bridge contacts-read
```

## Environment Variables

- `APPLE_BRIDGE_BIN` - Override path to the Swift binary
- `APPLE_BRIDGE_APP` - Override path to the AppleBridge `.app` bundle

## License

MIT
