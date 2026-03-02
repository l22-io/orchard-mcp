# Contributing to orchard-mcp

Thanks for your interest in contributing. This guide covers the development setup and workflow.

## Prerequisites

- macOS 14+ (Sonoma or later)
- Swift 5.9+ (Xcode Command Line Tools)
- Node.js 18+

## Development Setup

```bash
git clone git@github.com:l22-io/orchard-mcp.git
cd orchard-mcp
npm install
npm run build
```

This builds both the Swift binary (`apple-bridge`) and the TypeScript MCP server.

## Build Commands

```bash
npm run build          # Swift + TypeScript
npm run build:swift    # Swift only
npm run build:ts       # TypeScript only
npm run dev            # TypeScript watch mode
npm test               # Run test suite
npm run lint           # Type-check without emitting
```

## Architecture

Two-layer design:

1. **TypeScript MCP server** (`src/`) -- handles MCP protocol, Zod schemas, tool routing
2. **Swift CLI** (`swift/`) -- native binary using EventKit (Calendar/Reminders), AppleScript (Mail), FileManager/Spotlight/PDFKit (Files)

The TypeScript layer calls the Swift binary via `child_process.execFile` and parses JSON responses. All Swift subcommands return a `{"status": "ok"|"error", "data": ..., "error": ...}` envelope.

## Testing

```bash
npm test
```

Tests cover tool registration (all 28 tools) and bridge JSON contract validation. Manual testing on macOS is required for end-to-end verification since EventKit and AppleScript access real system data.

### macOS Sequoia TCC Note

macOS Sequoia requires an `.app` bundle for some EventKit permissions. The build process creates `AppleBridge.app` automatically. If you're testing Reminders features, run `orchard-mcp setup` first to trigger the TCC permission dialog.

## Making Changes

1. Create a branch from `main`
2. Make your changes
3. Run `npm test` and `npm run lint`
4. Commit using [conventional commits](https://www.conventionalcommits.org/) style:
   - `feat: add new calendar tool`
   - `fix: handle empty mail response`
   - `chore: update dependencies`
5. Open a pull request against `main`

## Pull Request Guidelines

- Keep PRs focused on a single change
- Include a test plan in the PR description
- Ensure `npm run build` and `npm test` pass
- Update `CHANGELOG.md` for user-facing changes

## Reporting Issues

- **Bugs**: Use the [bug report template](https://github.com/l22-io/orchard-mcp/issues/new?template=bug_report.md)
- **Features**: Use the [feature request template](https://github.com/l22-io/orchard-mcp/issues/new?template=feature_request.md)
- **Security**: See [SECURITY.md](SECURITY.md) for responsible disclosure

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
