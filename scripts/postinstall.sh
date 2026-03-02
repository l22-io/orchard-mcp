#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_BUNDLE="$PROJECT_ROOT/swift/.build/AppleBridge.app"

# Skip on non-macOS (shouldn't happen due to os field, but be safe)
if [ "$(uname)" != "Darwin" ]; then
    echo "[orchard-mcp] macOS required. Skipping postinstall."
    exit 0
fi

# Re-sign the .app bundle (ad-hoc signatures may not survive npm packaging)
if [ -d "$APP_BUNDLE" ]; then
    echo "[orchard-mcp] Codesigning AppleBridge.app..."
    codesign --force --sign - "$APP_BUNDLE" 2>/dev/null || true
    echo "[orchard-mcp] Ready. Run 'orchard-mcp setup' to configure permissions."
else
    echo "[orchard-mcp] Warning: AppleBridge.app not found. Run 'orchard-mcp setup' to build it."
fi
