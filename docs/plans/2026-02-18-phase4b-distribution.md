# Phase 4b: npm Distribution Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** `npm install -g apple-mcp` compiles Swift, builds .app bundle, and gives a working MCP server on any Mac.

**Architecture:** npm `postinstall` script handles Swift compilation and .app bundle creation. TypeScript is pre-compiled before publish. `setup.ts` skips build steps if artifacts already exist.

**Tech Stack:** npm packaging, bash postinstall script, existing Swift/TypeScript build

---

### Task 1: Create postinstall script

**Files:**
- Create: `scripts/postinstall.sh`

**Step 1: Create the script**

```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SWIFT_DIR="$PROJECT_ROOT/swift"
BRIDGE_BIN="$SWIFT_DIR/.build/release/apple-bridge"
APP_BUNDLE="$SWIFT_DIR/.build/AppleBridge.app"
INFO_PLIST="$SWIFT_DIR/Sources/AppleBridge/Info.plist"

# Skip if binary already exists (e.g. development environment)
if [ -f "$BRIDGE_BIN" ] && [ -d "$APP_BUNDLE" ]; then
    echo "[apple-mcp] Swift binary and .app bundle already exist, skipping build."
    exit 0
fi

# Check for Swift
if ! command -v swift &> /dev/null; then
    echo "[apple-mcp] Swift not found. Install Xcode Command Line Tools: xcode-select --install"
    echo "[apple-mcp] Then run: apple-mcp setup"
    exit 0
fi

# Check for macOS
if [ "$(uname)" != "Darwin" ]; then
    echo "[apple-mcp] macOS required. Skipping Swift build."
    exit 0
fi

echo "[apple-mcp] Building Swift binary..."
cd "$SWIFT_DIR"
swift build -c release \
    -Xlinker -sectcreate \
    -Xlinker __TEXT \
    -Xlinker __info_plist \
    -Xlinker Sources/AppleBridge/Info.plist

echo "[apple-mcp] Building AppleBridge.app bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp "$BRIDGE_BIN" "$APP_BUNDLE/Contents/MacOS/apple-bridge"
cp "$INFO_PLIST" "$APP_BUNDLE/Contents/"
codesign --force --sign - "$APP_BUNDLE"

echo "[apple-mcp] Build complete. Run 'apple-mcp setup' to configure permissions."
```

**Step 2: Make it executable**

Run: `chmod +x scripts/postinstall.sh`

**Step 3: Test it**

Run: `rm -rf swift/.build && bash scripts/postinstall.sh`
Expected: Swift builds, .app bundle created, "Build complete" message.

**Step 4: Test idempotency**

Run: `bash scripts/postinstall.sh`
Expected: "already exist, skipping build."

**Step 5: Commit**

```bash
git add scripts/postinstall.sh
git commit -m "feat(dist): add postinstall script for Swift build"
```

---

### Task 2: Update package.json for distribution

**Files:**
- Modify: `package.json`

**Step 1: Update package.json**

Changes needed:
1. Add `postinstall` script
2. Add `prepublishOnly` script
3. Expand `files` to include Swift source
4. Add `os` restriction

The full updated `package.json`:

```json
{
  "name": "apple-mcp",
  "version": "0.2.0",
  "description": "MCP server for Apple Calendar, Mail, and Reminders on macOS using native EventKit",
  "type": "module",
  "bin": {
    "apple-mcp": "./build/index.js"
  },
  "scripts": {
    "build": "npm run build:swift && npm run build:ts",
    "build:ts": "tsc && chmod 755 build/index.js",
    "build:swift": "cd swift && swift build -c release -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Sources/AppleBridge/Info.plist",
    "postinstall": "bash scripts/postinstall.sh",
    "prepublishOnly": "npm run build:ts",
    "dev": "tsc --watch",
    "start": "node build/index.js",
    "lint": "tsc --noEmit",
    "clean": "rm -rf build && cd swift && swift package clean"
  },
  "files": [
    "build",
    "scripts/postinstall.sh",
    "swift/Sources/",
    "swift/Package.swift",
    "swift/Package.resolved"
  ],
  "os": ["darwin"],
  "keywords": [
    "mcp",
    "apple",
    "calendar",
    "mail",
    "reminders",
    "eventkit",
    "macos",
    "model-context-protocol"
  ],
  "author": "l22.io GmbH",
  "license": "MIT",
  "engines": {
    "node": ">=18.0.0"
  },
  "dependencies": {
    "@modelcontextprotocol/sdk": "^1.24.0",
    "zod": "^3.25.0"
  },
  "devDependencies": {
    "@types/node": "^22.0.0",
    "typescript": "^5.7.0"
  }
}
```

Key changes:
- `postinstall`: runs `scripts/postinstall.sh` after install
- `prepublishOnly`: ensures TypeScript is compiled before `npm publish`
- `files`: includes Swift source + postinstall script, removes pre-built binary (compiled on target)
- `os`: `["darwin"]` signals macOS-only
- `build:swift`: now includes the `-Xlinker -sectcreate` flags for Info.plist embedding

**Step 2: Verify npm pack includes correct files**

Run: `npm pack --dry-run 2>&1 | head -40`
Expected: Should list `build/`, `scripts/postinstall.sh`, `swift/Sources/`, `swift/Package.swift`, `swift/Package.resolved`. Should NOT include `swift/.build/`.

**Step 3: Commit**

```bash
git add package.json
git commit -m "feat(dist): update package.json for npm distribution"
```

---

### Task 3: Update setup.ts to skip existing builds

**Files:**
- Modify: `src/setup.ts:112-140`

**Step 1: Update buildSwift function**

In `src/setup.ts`, modify the `buildSwift` function to check if the binary already exists:

```typescript
// Step 2: Build Swift
async function buildSwift(total: number): Promise<boolean> {
  step(2, total, "Building Swift binary...");

  if (existsSync(bridgeBin)) {
    log("Binary already exists -- skipping build.");
    return true;
  }

  try {
    await run(
      "swift",
      [
        "build", "-c", "release",
        "-Xlinker", "-sectcreate",
        "-Xlinker", "__TEXT",
        "-Xlinker", "__info_plist",
        "-Xlinker", "Sources/AppleBridge/Info.plist",
      ],
      { cwd: swiftDir, timeout: 300_000 }
    );
    log("swift build -c release -- ok");
    return true;
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    log(`Swift build failed: ${msg}`);
    return false;
  }
}
```

**Step 2: Update buildAppBundle function**

Modify `buildAppBundle` to check if the .app bundle already exists:

```typescript
// Step 3: Build .app bundle
async function buildAppBundle(total: number): Promise<void> {
  step(3, total, "Building AppleBridge.app bundle...");

  const macosDir = resolve(appBundle, "Contents", "MacOS");
  const binaryInApp = resolve(macosDir, "apple-bridge");

  if (existsSync(binaryInApp)) {
    log("App bundle already exists -- skipping build.");
    return;
  }

  mkdirSync(macosDir, { recursive: true });
  copyFileSync(bridgeBin, binaryInApp);
  copyFileSync(infoPlist, resolve(appBundle, "Contents", "Info.plist"));

  try {
    await run("codesign", ["--force", "--sign", "-", appBundle]);
    log("Created and signed -- ok");
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    log(`codesign failed: ${msg}`);
  }
}
```

**Step 3: Build TypeScript**

Run: `npx tsc`
Expected: No errors.

**Step 4: Test setup skips build**

Run: `node build/index.js setup --non-interactive`
Expected: Steps 2 and 3 show "already exists -- skipping build."

**Step 5: Commit**

```bash
git add src/setup.ts
git commit -m "feat(dist): skip build steps in setup if artifacts exist"
```

---

### Task 4: Add .npmignore

**Files:**
- Create: `.npmignore`

**Step 1: Create .npmignore**

The `files` field in package.json is an allowlist, but `.npmignore` provides extra safety:

```
# Development files
swift/.build/
docs/
*.ts
!*.d.ts
tsconfig.json
.github/
.git/
node_modules/
```

**Step 2: Verify package contents**

Run: `npm pack --dry-run 2>&1`
Expected: Only `build/`, `scripts/postinstall.sh`, `swift/Sources/`, `swift/Package.swift`, `swift/Package.resolved`, `package.json`, `LICENSE`, `README.md`. No `.build/`, no `.ts` source files, no `docs/`.

**Step 3: Commit**

```bash
git add .npmignore
git commit -m "feat(dist): add .npmignore for clean npm package"
```

---

### Task 5: End-to-end test

Test the full install flow by simulating what `npm install -g` does.

**Step 1: Clean slate**

```bash
cd swift && swift package clean && rm -rf .build && cd ..
```

**Step 2: Run postinstall**

```bash
bash scripts/postinstall.sh
```

Expected: Swift builds, .app bundle created.

**Step 3: Verify binary works**

```bash
./swift/.build/release/apple-bridge doctor
```

Expected: JSON output with status ok.

**Step 4: Verify .app bundle works**

```bash
TMPFILE=$(mktemp) && open -W -n -a swift/.build/AppleBridge.app --args reminder-lists --output "$TMPFILE" && cat "$TMPFILE" && rm "$TMPFILE"
```

Expected: JSON with reminder lists.

**Step 5: Verify setup skips builds**

```bash
node build/index.js setup --non-interactive
```

Expected: Steps 2 and 3 show "already exists".

**Step 6: Verify npm pack**

```bash
npm pack --dry-run 2>&1
```

Expected: Clean file list, reasonable tarball size.
