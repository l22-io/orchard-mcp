#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SWIFT_DIR="$PROJECT_ROOT/swift"
BRIDGE_BIN="$SWIFT_DIR/.build/release/apple-bridge"
APP_BUNDLE="$SWIFT_DIR/.build/AppleBridge.app"
INFO_PLIST="$SWIFT_DIR/Sources/AppleBridge/Info.plist"

LINKER_FLAGS="-Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker $INFO_PLIST"

echo "[prepublish] Building arm64 binary..."
cd "$SWIFT_DIR"
swift build -c release $LINKER_FLAGS --triple arm64-apple-macosx

echo "[prepublish] Building x86_64 binary..."
swift build -c release $LINKER_FLAGS --triple x86_64-apple-macosx

echo "[prepublish] Creating universal binary..."
lipo -create \
    .build/arm64-apple-macosx/release/apple-bridge \
    .build/x86_64-apple-macosx/release/apple-bridge \
    -output "$BRIDGE_BIN"

echo "[prepublish] Building AppleBridge.app bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp "$BRIDGE_BIN" "$APP_BUNDLE/Contents/MacOS/apple-bridge"
cp "$INFO_PLIST" "$APP_BUNDLE/Contents/"
codesign --force --sign - "$APP_BUNDLE"

echo "[prepublish] Writing checksum manifest..."
SHASUM_FILE="$APP_BUNDLE.sha256"
(cd "$APP_BUNDLE/Contents/MacOS" && shasum -a 256 apple-bridge) > "$SHASUM_FILE"
cat "$SHASUM_FILE"

echo "[prepublish] Verifying universal binary..."
file "$BRIDGE_BIN"

echo "[prepublish] Done."
echo "[prepublish] Publish this checksum alongside the GitHub release so users"
echo "             can cross-reference \$SHASUM_FILE against a trusted channel."
