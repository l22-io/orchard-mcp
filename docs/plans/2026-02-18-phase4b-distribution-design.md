# Phase 4b: npm Distribution Design

## Goal

`npm install -g apple-mcp` gives a working MCP server on any Mac. One command.

## How It Works

1. `npm install -g apple-mcp` installs the package
2. `postinstall` script compiles Swift binary + builds .app bundle + codesigns
3. Binary and .app bundle live inside the npm package directory
4. Run `apple-mcp setup` once to trigger TCC permissions and print MCP client config
5. `apple-mcp` starts the MCP server

## Changes Required

### package.json

- Add `postinstall` script pointing to `scripts/postinstall.sh`
- Expand `files` array to include Swift source (needed for compile on target machine):
  `swift/Sources/`, `swift/Package.swift`, `swift/Package.resolved`
- Keep `build/` in files (TypeScript is pre-compiled)
- Add `os: ["darwin"]` to signal macOS-only
- Add `prepublishOnly` script that runs `npm run build:ts` to ensure TS is compiled before publish

### scripts/postinstall.sh

New file. Handles:
1. Check for Swift (`swift --version`), skip gracefully if not found
2. `cd swift && swift build -c release` with Info.plist sectcreate flags
3. Build .app bundle (mkdir, copy binary, copy Info.plist, codesign)
4. Print success/failure message

Must be idempotent (safe to run multiple times). Uses `set -e` for fail-fast.

### bridge.ts path resolution

Current paths resolve relative to `__dirname` (the `build/` directory):
```
resolve(__dirname, "..", "swift", ".build", "release", "apple-bridge")
```

This already works for both development and npm global install because the directory structure is preserved. No change needed.

### setup.ts

Skip Swift build step (step 2) and .app bundle step (step 3) if the binary and .app already exist. The postinstall script already handles these.

## Out of Scope

- Homebrew tap
- Binary notarization
- GitHub Actions / CI
- MCP registry submissions
- Universal binary (arm64 + x86_64 fat binary)
- Public README polish

## Publish Flow

```bash
npm run build:ts        # compile TypeScript
npm publish             # publishes to npm (includes TS build + Swift source)
                        # postinstall on target machine compiles Swift
```
