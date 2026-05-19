# Changelog

## [0.6.2] - 2026-05-19

### Fixed
- **Mail.app re-lockup via two gaps in the v0.6.1 watchdog story.** v0.6.1 stopped the unbounded body-search lockup, but two adjacent code paths still produced orphaned `osascript` processes that wedged Mail.app's Apple Event queue:
  - `bridge.ts`: when the timeout fired, `SIGTERM` was sent to the process group and `SIGKILL` scheduled 2 s later — but the Swift bridge has no `SIGTERM` handler and dies on the first signal, so `child.on("close")` fired immediately and `settle()` cancelled the `SIGKILL` timer before it ran. Any `osascript` grandchild blocked in a Mach RPC to Mail.app/Notes.app then stayed alive with `PPID=1`, holding Mail's event queue indefinitely. The escalation is now sticky: once committed it cannot be cancelled by the parent's close, and the `SIGKILL` timer is `.unref()`d so it never blocks Node shutdown.
  - `Doctor.swift`: `checkMailAccess()` and `checkNotesAccess()` ran `osascript -e 'tell application "Mail" to count of accounts'` (and the Notes equivalent) with `task.waitUntilExit()` and no timeout. When Mail.app was busy, this blocked until Node's 30 s timer fired and then triggered the bug above — `system_doctor` was the actual orphan source observed in the field. Both checks now use a shared `runOsascriptBounded` helper with a 5 s `SIGTERM`/`SIGKILL` watchdog and report `accessible: false` with a clear note instead of waiting.
- Regression test in `tests/bridge.test.ts` reproduces the orphan: a stub bridge forks a stdio-detached perl grandchild that maps `SIGTERM` to `SIG_IGN`. Without the fix the grandchild survives the bridge timeout; with the fix it is `SIGKILL`ed after the grace period.

## [0.6.1] - 2026-05-13

### Fixed
- **Mail.app lockup from unbounded body searches.** `mail.search` with `searchIn` `body`/`all` + `mailbox: "all"` + no specific account issued an AppleScript that iterated `every message of every mailbox of every account` with `content contains`, forcing Mail to load message bodies en masse. Mail.app could be locked on Apple Event processing for many minutes, during which Force Quit / dock-quit did nothing (the quit Apple Event was queued behind the in-flight search). The TS bridge then orphaned the osascript subprocess when its timeout fired, leaving Mail wedged indefinitely.
  - `Mail.swift`: `MailBridge.search` now refuses the pathological combination before invoking Mail; clients get a clear error pointing at the narrowing options (`--account`, `--mailbox`, or `--search-in subject|sender`).
  - `Mail.swift`: `runAppleScript` now has a 90-second watchdog (`task.terminate()` followed by `SIGKILL` after a 2-second grace) so a hung script auto-frees Mail.app instead of holding it hostage forever.
  - `bridge.ts`: switched from `execFile` to `spawn` with `detached: true`; on timeout the entire process group is killed via `process.kill(-pid, "SIGTERM")` so `osascript` grandchildren are terminated alongside `apple-bridge` instead of being orphaned to `launchd`.
  - `bridge.ts`: added `BridgeOptions.timeoutMs` for per-call overrides; mail scan commands (`mail.search`, `mail.unread_summary`, `mail.flagged`) pass 120 s so the in-Swift 90 s watchdog surfaces a clean error before the TS-side kill cuts execution short.

### Changed
- **`npm run build:swift` now refreshes the `AppleBridge.app` bundle.** The TS bridge invokes the binary inside `swift/.build/AppleBridge.app/Contents/MacOS/apple-bridge`, but the previous `build:swift` only produced `.build/release/apple-bridge` — dev iterations silently ran against the stale `.app` copy. The script now also copies the freshly-built binary into the bundle, refreshes `Info.plist`, and re-`codesign`s, matching the logic in `scripts/postinstall.sh`'s `build_from_source`.

## [0.6.0] - 2026-05-12

### Changed
- TypeScript bumped to `^6.0.0` (from `^5.7.0`)
- `@types/node` bumped to `^25.0.0` (from `^22.0.0`)
- `zod` bumped to `^4.4.0` (from `^3.25.0`); existing schema surface (`z.string/number/object` + `.optional/.min/.max/.int/.describe`) is unchanged between v3 and v4 — no migration needed
- `swift-argument-parser` floor bumped to `1.7.1` (from `1.3.0`)
- `engines.node` minimum bumped to `>=22.0.0` (from `>=18.0.0`); Node 18 EOL was 2025-04-30, aligning with current LTS
- CI now tests on a Node `[22, 24]` matrix (was Node 18) to match the supported floor

### Fixed
- `tsconfig.json`: added `"types": ["node"]`. TS 6 no longer auto-discovers `@types/*` under Node16 module resolution; without this every `node:*` import failed to type-check

## [0.5.1] - 2026-05-12

### Security
- Bumped `@modelcontextprotocol/sdk` `^1.24.0` → `^1.29.0` and ran `npm audit fix`, clearing 7 transitive vulnerabilities (high/moderate) in the SDK's HTTP transport dependencies: Hono (auth bypass + path traversal), express, express-rate-limit (rate-limit bypass via IPv6), ajv, fast-uri (path traversal + host confusion), ip-address (XSS), path-to-regexp (ReDoS). Stdio transport never reached this code in practice, but bumping the floor lets npm pick up patched versions.

### Changed
- `@types/node` bumped to `^22.19.0` (within 22.x line, before the 0.6.0 jump to 25.x)
- `tsx` bumped to `^4.21.0`

## [0.3.3] - 2026-03-23

### Added
- Body search via `searchIn` parameter (subject, sender, body, or all fields)
- Cross-mailbox (`mailbox: "all"`) and cross-account (`account: "all"`) search
- Nested mailbox traversal in `mail.list_accounts` (recursive, path-like names)
- Pagination with opt-in `offset` parameter on `mail.search` and `mail.flagged`
- Body truncation on `mail.read_message` (default 4000 chars, configurable via `maxBodyLength`)
- Test suite for mail tool logic (`tests/mail.test.ts`)

### Fixed
- `readMessage` and `saveAttachment` fallback now searches all mailboxes (not just Proton's All Mail)

## [0.3.2] - 2026-03-04

### Added
- Package directory with manifest
- Banner image in README

## [0.3.1] - 2026-03-02

### Changed
- Ship prebuilt universal binary (arm64 + x86_64) in npm package -- no Swift or Xcode required to install
- Postinstall now only codesigns the .app bundle instead of compiling Swift from source
- Updated MCP client configuration examples to use `npx @l22-io/orchard-mcp`

### Added
- GitHub Actions CI workflow (lint, build, test)
- SECURITY.md with GitHub private vulnerability reporting
- Issue template config (blank issues disabled, Discussions link)
- `scripts/prepublish.sh` for building universal binary at publish time

## [0.3.0] - 2026-03-01

### Added
- Files tools: `files.list`, `files.info`, `files.search`, `files.read`, `files.move`, `files.copy`, `files.create_folder`, `files.trash`
- `mail.save_attachment` tool for saving email attachments to disk
- Setup wizard (`orchard-mcp setup`) for guided first-run configuration
- .app bundle fallback for macOS Sequoia TCC permissions
- Automated test suite (tool registration + bridge contract)
- LICENSE (MIT)
- npm package scoped as `@l22-io/orchard-mcp`

### Changed
- Package name from `apple-mcp` to `@l22-io/orchard-mcp`
- `mail.read_message` now returns attachment metadata (name, MIME type, index)

### Fixed
- MIME type error handling in mail attachment operations
- POSIX file path concatenation in `saveAttachment`

## [0.2.0] - 2025-12-15

### Added
- Mail tools: `mail.list_accounts`, `mail.unread_summary`, `mail.search`, `mail.read_message`, `mail.flagged`, `mail.create_draft`
- Reminders tools: full CRUD (`list_lists`, `list_reminders`, `today`, `create_list`, `create_reminder`, `complete_reminder`, `delete_reminder`, `delete_list`)
- `system.doctor` diagnostic tool

## [0.1.0] - 2025-10-01

### Added
- Calendar tools: `calendar.list_calendars`, `calendar.list_events`, `calendar.today`, `calendar.search`
- Swift bridge architecture (TypeScript MCP server + native Swift CLI)
- EventKit integration for Calendar and Reminders
- AppleScript integration for Mail
