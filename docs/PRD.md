# apple-mcp -- Product Requirements Document

## Problem

LLM agents (Claude, Warp, Cursor, etc.) running on macOS have no reliable, unified way to access Apple Calendar, Mail, and Reminders. Current options are:





No single server combines Calendar + Mail + Reminders with native framework access in a production-quality, distributable package.

## Product Vision

**apple-mcp** is a macOS-native MCP server that gives any MCP-compatible client (Warp, Claude Desktop, Claude Code, Cursor, etc.) structured access to Apple Calendar, Apple Mail, and Apple Reminders through native macOS frameworks.

It is designed to be:

- **Reliable**: Uses EventKit (Calendar/Reminders) and Mail.app ScriptingBridge/AppleScript (Mail) instead of brittle hacks
- **Universal**: Works from any MCP client via stdio transport -- no per-client permission configuration
- **Distributable**: Installable via npm (`npx apple-mcp`) with a compiled Swift helper binary
- **Privacy-first**: Runs entirely locally, no cloud dependencies, no data leaves the machine

## Architecture













## Architecture

### Two-layer design

```
MCP Client (Warp/Claude/Cursor)
  -- stdio JSON-RPC -->
TypeScript MCP Server (Node.js)
  -- child_process.execFile -->
Swift CLI helpers (native macOS binaries)
  -- EventKit / ScriptingBridge -->
macOS Calendar.app / Mail.app / Reminders.app
```

### TypeScript layer (`src/`)

- MCP server using `@modelcontextprotocol/sdk` with `StdioServerTransport`
- Zod schemas for all tool inputs
- Calls Swift CLI helpers, parses JSON responses
- Error handling, logging (stderr only for stdio transport)
- No direct macOS framework access -- all native calls delegated to Swift

### Swift layer (`swift/`)

Single binary (`apple-bridge`) with subcommands:

- `apple-bridge calendars` -- list all calendars with account info
- `apple-bridge events --start <ISO> --end <ISO> [--calendar <id>]` -- fetch events (recurring expanded)
- `apple-bridge search <query> --start <ISO> --end <ISO>` -- search events by text
- `apple-bridge reminders [--list <name>] [--due-within <range>]` -- fetch reminders (planned)
- `apple-bridge reminder-lists` -- list reminder lists (planned)
- `apple-bridge mail-accounts` -- list mail accounts with mailboxes and unread counts
- `apple-bridge mail-unread [--limit <n>]` -- unread summary per account with recent message headers
- `apple-bridge mail-search --query <q> [--account <name>] [--mailbox <name>] [--limit <n>]` -- search messages by subject/sender
- `apple-bridge mail-message --id <id>` -- get full message content
- `apple-bridge mail-flagged [--limit <n>]` -- list flagged messages across accounts
- `apple-bridge doctor` -- check permissions, list accessible accounts

All subcommands output JSON envelope: `{"status": "ok"|"error", "data": ..., "error": ...}`

### Permission model

**No OAuth or web-based authentication required.** apple-mcp reads from the local
macOS data stores (EventKit, Mail.app) which are already populated by accounts
configured in macOS System Settings > Internet Accounts. The OS handles all OAuth
flows with Google, Microsoft, iCloud, etc. natively. apple-mcp never communicates
with any remote service.

The only permissions apple-mcp needs are macOS TCC (Transparency, Consent, and Control) grants:

- Calendar + Reminders: EventKit `requestFullAccessToEvents()` / `requestFullAccessToReminders()` -- one-time macOS prompt on first run
- Mail: AppleScript Automation permission (`osascript`) -- prompted by macOS on first mail access
- The `apple-bridge doctor` subcommand checks all permissions and guides the user through granting them
- Permissions are granted to the **Swift binary itself**, not to the calling app -- works from any MCP client

This avoids the complexity of directly integrating with Google Calendar API or
Microsoft Graph directly -- those require OAuth client IDs, redirect URIs, token refresh,
and managing credentials per provider. apple-mcp avoids all of that by piggybacking on
OS-level authentication.

## MCP Tools (v1 scope)

### Calendar

- `calendar.list_calendars` -- List all calendars with account name, color, type (local/CalDAV/Exchange), read-only status
- `calendar.list_events` -- Events in a date range, with optional calendar filter. Recurring events properly expanded via `predicateForEvents`. Returns: title, start, end, location, calendar, notes, attendees, is_all_day
- `calendar.today` -- Shortcut: today's events across all calendars
- `calendar.search` -- Search events by title/notes within a date range

### Mail

- `mail.list_accounts` -- List all configured mail accounts and their mailboxes
- `mail.unread_summary` -- Unread count per account/mailbox, with subject lines of recent unread
- `mail.search` -- Search messages by sender, subject, date range, read/unread, flagged. Returns headers only (no body) for performance.
- `mail.read_message` -- Get full message content by ID
- `mail.flagged` -- List flagged messages across all accounts

### Reminders

- `reminders.list_lists` -- List all reminder lists
- `reminders.list_reminders` -- Reminders from a list, with filters (due today, overdue, completed, priority)
- `reminders.today` -- Shortcut: reminders due today + overdue across all lists

### System

- `system.doctor` -- Check permissions status, list accessible accounts/calendars, report version

## Setup & Onboarding

### Interactive setup wizard (`apple-mcp setup`)

A CLI-first interactive setup command that handles the full onboarding flow:

1. **Prerequisite checks**: macOS version (14+), Xcode CLI tools (if building from source), Node.js version
2. **Binary acquisition**: Compile Swift from source or download pre-built universal binary from GitHub Releases
3. **TCC permission triggers**: Run `apple-bridge doctor` which calls `requestFullAccessToEvents()`, triggering the system permission dialog. Verify the grant was accepted.
4. **MCP client detection and config**: Detect installed MCP clients (Warp, Claude Desktop, Cursor, Claude Code) and output or write the correct JSON/CLI config snippet
5. **Validation**: Run `apple-bridge calendars` and confirm accounts are visible. Report account count and names.

Design principles:
- CLI-first, not GUI. Supports `--non-interactive` flag for scripted installs.
- All state is queryable via `apple-bridge doctor` (foundation for a future management UI).
- No web-based authentication flows. All account auth is handled at the OS level.
- Idempotent: safe to re-run if permissions change or new MCP clients are installed.

### Future: Management frontend

A lightweight local web dashboard (localhost) is planned for post-v1:
- Show connected accounts, calendars, permission status
- Toggle which calendars/mailboxes are exposed via MCP
- View logs, test connections
- Implementation: minimal HTTP server (Hono/Fastify on localhost), reads same config as MCP server
- Not a desktop app -- just a browser tab

## Distribution

### npm package

- Package name: `apple-mcp` (or `@l22-io/apple-mcp` if scoped)
- Install: `npx apple-mcp` or `npm install -g apple-mcp`
- The npm package includes the pre-compiled Swift binary for the current architecture (arm64/x86_64)
- Build step: `npm run build` compiles TypeScript + Swift
- Alternative: users can compile Swift from source if they prefer

### Pre-built binaries

- Ship universal binary (arm64 + x86_64) via GitHub Releases
- Setup wizard downloads correct binary automatically
- Homebrew tap (`brew install l22-io/tap/apple-bridge`) as alternative channel
- Binary must be notarized for macOS Gatekeeper (required for distribution outside App Store)

### MCP client configuration

Generated by `apple-mcp setup`. Manual alternatives:

Warp:
```json
{"command": "npx", "args": ["apple-mcp"]}
```

Claude Desktop (`claude_desktop_config.json`):
```json
{"mcpServers": {"apple": {"command": "npx", "args": ["apple-mcp"]}}}
```

Claude Code:
```bash
claude mcp add --scope user apple -- npx apple-mcp
```

## Requirements

- macOS 14+ (Sonoma or later) -- EventKit full access APIs
- Swift 5.9+ (ships with Xcode 15+, or Xcode Command Line Tools)
- Node.js 18+
- No Docker (native macOS framework access required)

## Development Phases

### Phase 1: Calendar + System -- COMPLETE

- Swift CLI: `calendars`, `events`, `search`, `doctor`
- TypeScript MCP: `calendar.list_calendars`, `calendar.list_events`, `calendar.today`, `calendar.search`, `system.doctor`
- Permission flow: first-run prompt for Calendar access
- Tested with Warp MCP and Claude Desktop
- Unblocked calendar access for production use cases

### Phase 2: Reminders -- PLANNED

- Swift CLI: `reminders`, `reminder-lists`
- TypeScript MCP: `reminders.list_lists`, `reminders.list_reminders`, `reminders.today`
- Relevant for potential Todoist-to-Apple-Reminders migration

### Phase 3: Mail -- COMPLETE

- Swift CLI: `mail-accounts`, `mail-unread`, `mail-search`, `mail-message`, `mail-flagged`
- TypeScript MCP: `mail.list_accounts`, `mail.unread_summary`, `mail.search`, `mail.read_message`, `mail.flagged`
- Mail access uses AppleScript via `osascript` with delimited output (`###`, `|||`, `^^^`, `::` separators) parsed in Swift
- All scripts include `try` blocks for resilience across heterogeneous account types (IMAP, Exchange, iCloud)
- Tested with 10+ real accounts across iCloud, Gmail, Google Workspace, Proton, and Exchange
- Alternative: direct SQLite DB read for better performance, but requires Full Disk Access

### Phase 4: Setup Wizard & Distribution

- `apple-mcp setup` interactive CLI wizard (prerequisite checks, binary acquisition, TCC permission triggers, MCP client config generation, validation)
- `--non-interactive` flag for scripted/CI use
- Pre-built universal binary (arm64 + x86_64) via GitHub Releases
- Binary notarization for macOS Gatekeeper
- npm package with pre-built Swift binary
- MCP Inspector testing
- Publish to npm (decide scoped vs unscoped name)
- Homebrew tap for apple-bridge binary
- Submit to MCP server registries (PulseMCP, Glama, LobeHub)

### Future (post-v1)

- Write operations: create/update/delete events, complete reminders, send mail (with confirmation prompts)
- **Apple Notes**: list, search, read notes (AppleScript / ScriptingBridge)
- **Apple Pages/Numbers/Keynote**: list recent documents, read content/export, metadata access (ScriptingBridge)
- Contacts integration
- Streamable HTTP transport option (for remote scenarios)
- Local management frontend (localhost web dashboard for accounts, permissions, calendar toggles)

## Open Questions

1. **Package name**: `apple-mcp` (simple) vs `@l22-io/apple-mcp` (scoped) vs `macos-mcp`?
***REMOVED***
***REMOVED***
2. **Binary distribution**: Ship pre-compiled arm64 binary in npm package? Or require users to compile Swift from source? (arm64-only initially since x86 Macs are rare now)
***REMOVED***
