# Changelog

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
