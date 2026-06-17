# AGENTS.md

This file provides repository guidance for coding agents working in this repository.

## Project Overview

orchard-mcp is an MCP (Model Context Protocol) server that exposes macOS system services and apps (Calendar, Mail, Reminders, Files, Numbers, Pages, Keynote, Notes, Contacts) to MCP clients. It uses a two-layer architecture: a TypeScript MCP server communicates over stdio JSON-RPC, and delegates to a native Swift CLI binary (`apple-bridge`) that talks to macOS frameworks (EventKit, Contacts, PDFKit, Vision, etc.) and apps via AppleScript/JXA.

## Commands

```bash
npm run build          # Build both Swift binary + TypeScript
npm run build:ts       # TypeScript only
npm run build:swift    # Swift binary only
npm run dev            # TypeScript watch mode
npm test               # All tests (node:test via tsx)
npx tsx --test tests/bridge.test.ts   # Single test file
npm run lint           # Type-check (tsc --noEmit)
npm start              # Run the MCP server
```

## Architecture

```text
MCP Client (stdio JSON-RPC) -> TypeScript Server (Node.js) -> Swift CLI (apple-bridge) -> macOS Frameworks
```

**Entry point:** `src/index.ts` creates `McpServer`, registers tools from 10 modules, connects `StdioServerTransport`, and handles the `orchard-mcp setup` subcommand before server startup.

**Bridge layer:** `src/bridge.ts` executes the Swift binary, parses the `{status, data, error}` JSON envelope, and automatically retries via the `.app` bundle on "access denied" errors required for some macOS TCC permissions. `bridgeData(args)` is the convenience wrapper that throws on error.

**Tool modules:** `src/tools/*.ts` each exports a `register*Tools(server)` function. Tools use `server.tool(name, description, zodSchema, asyncHandler)`. Tool names are namespaced: `calendar.*`, `mail.*`, `reminders.*`, `files.*`, `system.*`, `numbers.*`, `pages.*`, `keynote.*`, `notes.*`, `contacts.*`. 65 tools total.

**Swift bridge:** `swift/Sources/AppleBridge/` contains a Swift CLI using ArgumentParser. Each subcommand maps to a tool. All output goes through `JSONOutput.success(data)` or `JSONOutput.error(msg)` to maintain the JSON envelope contract.

**stdout is reserved** for JSON-RPC in stdio transport. All diagnostics use stderr.

## Key Patterns

- Tool handlers call `bridgeData(["subcommand", "--flag", value])` and return `{content: [{type: "text", text: JSON.stringify(data, null, 2)}]}`
- Zod schemas validate all tool inputs
- Swift subcommands use `ParsableCommand` (sync) or `AsyncParsableCommand` (async for EventKit)
- Mail tools use AppleScript (`osascript`); Calendar and Reminders use native EventKit
- iWork tools (Numbers, Pages, Keynote) use AppleScript for document operations; Numbers bulk cell ops use JXA for native JSON
- iWork file paths are validated via `FilesBridge.validatePath()` and must be under `~/`
- Export subcommands use `--dest`, not `--output`, because `--output` is reserved for `.app` bundle mode JSON redirection
- Environment overrides: `APPLE_BRIDGE_BIN`, `APPLE_BRIDGE_APP`

## Requirements

macOS 14+, Swift 5.9+, Node.js 22+

## Related Documents

Project documents live in the Obsidian vault at `~/repos/obsidian-memory/l22.io/`:

- **PRD**: `~/repos/obsidian-memory/l22.io/orchard-mcp-PRD.md`
- **AGENTS.md backup**: `~/repos/obsidian-memory/l22.io/orchard-mcp-AGENTS.md`

When changing this file, also update the Obsidian backup at `~/repos/obsidian-memory/l22.io/orchard-mcp-AGENTS.md`.
