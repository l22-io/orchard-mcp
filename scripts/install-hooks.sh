#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOKS_DIR="$REPO_ROOT/.git/hooks"

mkdir -p "$HOOKS_DIR"
ln -sf "../../scripts/pre-commit-pii.sh" "$HOOKS_DIR/pre-commit"
chmod +x "$SCRIPT_DIR/pre-commit-pii.sh"

echo "[install-hooks] pre-commit hook installed -> scripts/pre-commit-pii.sh"
echo "[install-hooks] Blocks: phone numbers (+cc), personal emails, IBAN, SWIFT/BIC"
echo "[install-hooks] Bypass with: git commit --no-verify"
