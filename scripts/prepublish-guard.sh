#!/bin/bash
set -euo pipefail

fail() {
  echo "[prepublish-guard] $1" >&2
  exit 1
}

if [ "${ORCHARD_SKIP_PUBLISH_GUARD:-}" = "1" ]; then
  echo "[prepublish-guard] Skipping release guard because ORCHARD_SKIP_PUBLISH_GUARD=1."
  exit 0
fi

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

PACKAGE_NAME="$(node -p "require('./package.json').name")"
PACKAGE_VERSION="$(node -p "require('./package.json').version")"
CURRENT_BRANCH="$(git branch --show-current)"

if [ "$CURRENT_BRANCH" != "main" ]; then
  fail "Refusing to publish $PACKAGE_NAME@$PACKAGE_VERSION from branch '$CURRENT_BRANCH'. Switch to main first."
fi

git diff --quiet || fail "Refusing to publish with unstaged changes."
git diff --cached --quiet || fail "Refusing to publish with staged but uncommitted changes."

git fetch --quiet origin main

git merge-base --is-ancestor HEAD origin/main ||
  fail "Refusing to publish because local main is ahead of origin/main. Push main first."

git merge-base --is-ancestor origin/main HEAD ||
  fail "Refusing to publish because local main is behind origin/main. Pull first."

NPM_ERROR_FILE="$(mktemp)"
trap 'rm -f "$NPM_ERROR_FILE"' EXIT

if npm view "$PACKAGE_NAME@$PACKAGE_VERSION" version --json > /dev/null 2>"$NPM_ERROR_FILE"; then
  fail "$PACKAGE_NAME@$PACKAGE_VERSION already exists on npm. Bump package.json before publishing."
fi

if ! grep -q "E404" "$NPM_ERROR_FILE"; then
  cat "$NPM_ERROR_FILE" >&2
  fail "Could not verify whether $PACKAGE_NAME@$PACKAGE_VERSION exists on npm."
fi

echo "[prepublish-guard] Release guard passed for $PACKAGE_NAME@$PACKAGE_VERSION."
