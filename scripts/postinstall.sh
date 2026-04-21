#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SWIFT_DIR="$PROJECT_ROOT/swift"
APP_BUNDLE="$SWIFT_DIR/.build/AppleBridge.app"
BRIDGE_BIN="$SWIFT_DIR/.build/release/apple-bridge"
INFO_PLIST="$SWIFT_DIR/Sources/AppleBridge/Info.plist"
SHASUM_FILE="$SWIFT_DIR/.build/AppleBridge.app.sha256"
INNER_BIN="$APP_BUNDLE/Contents/MacOS/apple-bridge"

if [ "$(uname)" != "Darwin" ]; then
    echo "[orchard-mcp] macOS required. Skipping postinstall."
    exit 0
fi

build_from_source() {
    echo "[orchard-mcp] Swift detected -- building apple-bridge from source."
    (
        cd "$SWIFT_DIR"
        swift build -c release \
            -Xlinker -sectcreate \
            -Xlinker __TEXT \
            -Xlinker __info_plist \
            -Xlinker "$INFO_PLIST"
    )
    mkdir -p "$APP_BUNDLE/Contents/MacOS"
    cp "$BRIDGE_BIN" "$INNER_BIN"
    cp "$INFO_PLIST" "$APP_BUNDLE/Contents/Info.plist"
    codesign --force --sign - "$APP_BUNDLE" 2>/dev/null || true
    echo "[orchard-mcp] Built from source. Run 'orchard-mcp setup' to configure permissions."
}

verify_prebuilt() {
    # Defence-in-depth for the prebuilt fallback: compare the binary's hash
    # against the shipped manifest. This catches truncated/corrupted tarball
    # extraction but does NOT defend against a coordinated tarball tamper
    # (attacker would update both files). For a real chain of trust, install
    # with `npm install --ignore-scripts` and build from source, or wait for
    # a Developer ID signed release.
    if [ ! -f "$SHASUM_FILE" ]; then
        echo "[orchard-mcp] Warning: no checksum manifest shipped; skipping integrity check."
        return 0
    fi
    if [ ! -f "$INNER_BIN" ]; then
        return 1
    fi
    local expected actual
    expected=$(awk '{print $1}' "$SHASUM_FILE")
    actual=$(shasum -a 256 "$INNER_BIN" | awk '{print $1}')
    if [ "$expected" != "$actual" ]; then
        echo "[orchard-mcp] ERROR: Binary checksum mismatch."
        echo "             expected: $expected"
        echo "             actual:   $actual"
        echo "             The prebuilt binary may be corrupted or tampered with."
        echo "             Install Xcode Command Line Tools (xcode-select --install)"
        echo "             and reinstall to build from source instead."
        return 2
    fi
    echo "[orchard-mcp] Prebuilt binary checksum ok: $actual"
    return 0
}

if command -v swift >/dev/null 2>&1; then
    build_from_source
    exit 0
fi

echo "[orchard-mcp] Swift not available -- using prebuilt binary."
echo "             Install Xcode Command Line Tools for a higher-assurance"
echo "             install that builds apple-bridge locally."

if [ ! -d "$APP_BUNDLE" ]; then
    echo "[orchard-mcp] Warning: AppleBridge.app not found and Swift is unavailable."
    echo "             Install Xcode Command Line Tools and run 'orchard-mcp setup'."
    exit 0
fi

set +e
verify_prebuilt
status=$?
set -e
if [ $status -eq 2 ]; then
    exit 1
fi

echo "[orchard-mcp] Codesigning prebuilt AppleBridge.app..."
codesign --force --sign - "$APP_BUNDLE" 2>/dev/null || true
echo "[orchard-mcp] Ready. Run 'orchard-mcp setup' to configure permissions."
