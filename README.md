# apple-mcp

MCP server for Apple Calendar, Mail, and Reminders on macOS using native EventKit.

Gives any MCP-compatible client (Warp, Claude Desktop, Claude Code, Cursor) structured
access to your local Apple Calendar, Apple Mail, and Apple Reminders through native
macOS frameworks. No cloud dependencies, no OAuth setup -- all data stays local.

## How it works

apple-mcp reads from the local macOS data stores (EventKit for Calendar/Reminders,
AppleScript for Mail) which are already populated by accounts configured in
**System Settings > Internet Accounts**. The OS handles all authentication with Google,
Microsoft, iCloud, etc. natively. apple-mcp never communicates with any remote service
and requires no OAuth client IDs, redirect URIs, or token management.

The only permissions needed are macOS TCC grants (e.g. "Allow access to Calendars"),
triggered automatically on first run.

## Status

- Phase 1 (Calendar + System) -- complete
- Phase 3 (Mail) -- complete
- Phase 2 (Reminders) and Phase 4 (Setup Wizard & Distribution) -- planned

See `docs/PRD.md` for the full roadmap.

## Requirements

- macOS 14+ (Sonoma or later)
- Swift 5.9+ (Xcode Command Line Tools)
- Node.js 18+

## Setup

### From source (development)

```bash
# Clone and build
git clone git@github.com:l22-io/apple-mcp.git
cd apple-mcp
npm install
npm run build

# First run -- triggers macOS permission prompts
./swift/.build/release/apple-bridge doctor
```

### Setup wizard (planned)

```bash
npx apple-mcp setup
```

The setup wizard will handle prerequisite checks, binary compilation or download,
TCC permission grants, MCP client detection, and config generation. See `docs/PRD.md`
for details.

## MCP Client Configuration

### Warp

Add as an MCP server in Warp settings with:
```json
{"command": "node", "args": ["/path/to/apple-mcp/build/index.js"]}
```

### Claude Desktop

Edit `~/Library/Application Support/Claude/claude_desktop_config.json`:
```json
{
  "mcpServers": {
    "apple": {
      "command": "node",
      "args": ["/path/to/apple-mcp/build/index.js"]
    }
  }
}
```

### Claude Code

```bash
claude mcp add --scope user orchard -- node /path/to/apple-mcp/build/index.js
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
apple-bridge mail-accounts           List mail accounts and mailboxes
apple-bridge mail-unread             Unread summary per account (--limit)
apple-bridge mail-search             Search messages (--query, --account, --mailbox, --limit)
apple-bridge mail-message            Full message content (--id)
apple-bridge mail-flagged            Flagged messages (--limit)
apple-bridge doctor                  Check permissions and accessible resources
```

## Environment Variables

- `APPLE_BRIDGE_BIN` -- Override path to the Swift binary (default: `swift/.build/release/apple-bridge`)

## License

MIT
