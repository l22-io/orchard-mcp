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

# Check for macOS
if [ "$(uname)" != "Darwin" ]; then
    echo "[apple-mcp] macOS required. Skipping Swift build."
    exit 0
fi

# Check for Swift
if ! command -v swift &> /dev/null; then
    echo "[apple-mcp] Swift not found. Install Xcode Command Line Tools: xcode-select --install"
    echo "[apple-mcp] Then run: apple-mcp setup"
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
