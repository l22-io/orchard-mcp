# Phase 4a: Setup Wizard Design

## Goal

Interactive CLI wizard (`apple-mcp setup`) that handles prerequisites, building, TCC permissions, and MCP client configuration. Distribution/npm publishing is deferred to a follow-up.

## Decisions

- **Scope**: Setup wizard only (no npm publish, no universal binaries, no Homebrew)
- **Language**: TypeScript, runs as `apple-mcp setup`
- **MCP clients**: Warp + Claude Code (detect and print config snippets)
- **TCC**: Wizard builds AppleBridge.app, signs it, uses `open` for Reminders permission
- **Dependencies**: Zero new deps, raw Node readline for prompts
- **Config files**: Print snippets for user to paste, don't auto-write

## Entry Point

`apple-mcp setup` triggers the wizard. `apple-mcp` with no args remains the MCP server (unchanged). Check `process.argv[2] === "setup"` in `index.ts`.

`--non-interactive` flag: skip TCC prompts (report current status only), no waiting.

## Wizard Steps

### 1. Prerequisites

Check macOS version (14+), Swift availability, Node version. Fail fast with clear message.

### 2. Build Swift binary

Run `swift build -c release` with `-Xlinker -sectcreate` flags for Info.plist embedding.

### 3. Build .app bundle

Create `AppleBridge.app/Contents/{Info.plist,MacOS/apple-bridge}`, copy binary, sign with `codesign --force --sign -`.

### 4. TCC permissions

- Calendar: run `apple-bridge calendars` to trigger prompt, verify via doctor
- Reminders: run `open AppleBridge.app --args reminder-lists --output <tmp>` for .app bundle TCC dialog
- Mail: run `apple-bridge mail-accounts` to trigger Automation permission
- Report status of each

### 5. MCP client configuration

Detect Warp and Claude Code. Print config command/snippet for each. Don't auto-write.

### 6. Validation

Run `apple-bridge doctor`, display summary: calendar count, reminder list count, mail account count.

## Output Style

Plain text, no colors, no spinners. Step-based format:

```
apple-mcp setup
================

[1/6] Checking prerequisites...
      macOS 15.3 (Sequoia) -- ok
      Swift 5.9 -- ok
      Node.js 22.0 -- ok

[2/6] Building Swift binary...
      swift build -c release -- ok

[3/6] Building AppleBridge.app bundle...
      Created and signed -- ok

[4/6] Requesting permissions...
      Calendar: fullAccess -- ok
      Reminders: grant access in the dialog that appeared...
      Reminders: fullAccess -- ok
      Mail: accessible (10 accounts) -- ok

[5/6] MCP client configuration
      Warp: Add this MCP server config:
        {"command": "node", "args": ["/path/to/build/index.js"]}

      Claude Code:
        claude mcp add --scope user orchard -- node /path/to/build/index.js

[6/6] Validation
      Calendar: 26 calendars across 10 accounts
      Reminders: 3 lists (2,190 items)
      Mail: 10 accounts

      Ready to use.
```

`--non-interactive`: skips TCC prompts, reports current status, exits 0 (all granted) or 1 (missing).

## File Structure

- Create: `src/setup.ts` -- wizard logic, `runSetup()` export
- Modify: `src/index.ts` -- arg check for "setup"
