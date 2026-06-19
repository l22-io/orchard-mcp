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

- `mail_save_attachment` requires `account` and `mailbox` from a recent Mail result.
- Notes body/all search is refused; use title search, then `notes_read_note`.
- `numbers_read` and `numbers_get_formulas` require a cell range.
- PNG/JPEG Keynote export requires a single slide index.
- Calendar list/search ranges are capped at 31 days.

See [docs/app-safety-audit.md](docs/app-safety-audit.md) for the current audit and
guardrails.

The only permissions needed are macOS TCC grants (for example, "Allow access to
Calendars"), triggered automatically on first use or during setup.

## Status

Current release: 65 tools across Calendar, Mail, Reminders, Files, System, Numbers,
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

## Available Tools

Tool names use underscores for Claude Desktop Chat compatibility.

### Calendar

- `calendar_list_calendars` - List all calendars with account, type, color
- `calendar_list_events` - Events in a date range (recurring events expanded)
- `calendar_today` - Today's events across all calendars
- `calendar_search` - Search events by title, notes, or location

### Mail

- `mail_list_accounts` - List mail accounts with a bounded mailbox-name sample; use `mail_unread_summary` for unread counts
- `mail_unread_summary` - Unread count per account with recent message headers
- `mail_search` - Search messages by subject, sender, body, or all fields with pagination
- `mail_read_message` - Get message content by ID with configurable body truncation; pass account/mailbox locators when available
- `mail_flagged` - List flagged messages across all accounts with pagination
- `mail_create_draft` - Create a draft email in Mail.app for review
- `mail_save_attachment` - Save an email attachment to disk by message ID, index, account, and mailbox

### Reminders

- `reminders_list_lists` - List all reminder lists with account, color, item count
- `reminders_list_reminders` - Reminders from a list with filters
- `reminders_today` - Incomplete reminders due today plus overdue reminders
- `reminders_create_list` - Create a new reminder list
- `reminders_create_reminder` - Create a reminder with optional due date, priority, notes
- `reminders_complete_reminder` - Mark a reminder as completed
- `reminders_delete_reminder` - Delete a reminder
- `reminders_delete_list` - Delete a reminder list

### Files

- `files_list` - List directory contents with metadata
- `files_info` - Get detailed file metadata including Spotlight attributes
- `files_search` - Search files using macOS Spotlight
- `files_read` - Read or extract text from plain text, PDF, images, `.docx`, `.rtf`, `.pages`
- `files_move` - Move or rename files and folders, including batch operations
- `files_copy` - Copy a file or folder
- `files_create_folder` - Create a new directory
- `files_trash` - Move a file or folder to Trash

### System

- `system_doctor` - Check permissions and list accessible accounts/apps

### Numbers

- `numbers_search` - Find Numbers spreadsheets with Spotlight
- `numbers_read` - Read table data from a spreadsheet within a required cell range
- `numbers_write` - Write table data to a spreadsheet
- `numbers_create` - Create a new spreadsheet
- `numbers_list_sheets` - List sheets and tables
- `numbers_add_sheet` - Add a sheet
- `numbers_remove_sheet` - Remove a sheet
- `numbers_get_formulas` - Read formulas within a required cell range
- `numbers_export` - Export as CSV, PDF, or XLSX
- `numbers_info` - Inspect spreadsheet metadata

### Pages

- `pages_search` - Find Pages documents with Spotlight
- `pages_read` - Read document text
- `pages_write` - Replace document text
- `pages_create` - Create a new document
- `pages_find_replace` - Find and replace text
- `pages_insert_table` - Insert table data
- `pages_list_sections` - List document sections
- `pages_export` - Export as PDF, DOCX, TXT, or EPUB
- `pages_info` - Inspect document metadata

### Keynote

- `keynote_search` - Find Keynote decks with Spotlight
- `keynote_read` - Read slide content
- `keynote_create` - Create a new deck
- `keynote_add_slide` - Add a slide
- `keynote_edit_slide` - Edit slide title, body, or notes
- `keynote_remove_slide` - Remove a slide
- `keynote_reorder_slides` - Move slides
- `keynote_list_slides` - List slides
- `keynote_list_themes` - List available themes
- `keynote_export` - Export as PDF, PPTX, PNG, or JPEG; PNG/JPEG requires a slide index
- `keynote_info` - Inspect deck metadata

### Notes

- `notes_list_folders` - List Notes folders
- `notes_list_notes` - List notes with optional folder filtering
- `notes_search` - Search notes by title; body/all search is refused for app safety
- `notes_read_note` - Read a note by ID

### Contacts

- `contacts_list_groups` - List contact groups
- `contacts_search` - Search contacts
- `contacts_read_contact` - Read full contact details by ID

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
