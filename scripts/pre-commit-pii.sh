#!/bin/bash
# Block commits that introduce likely personal data (phone numbers with country
# codes, personal email addresses, IBANs, swiftcodes-looking strings).
#
# Install with: bash scripts/install-hooks.sh
#
# Bypass (not recommended): git commit --no-verify

set -e

# Only inspect lines being *added*.
diff=$(git diff --cached --diff-filter=AM -U0 -- ':(exclude)*.lock' ':(exclude)*.resolved' ':(exclude)package-lock.json' | grep -E '^\+[^+]' || true)

if [ -z "$diff" ]; then
    exit 0
fi

hits=0

check() {
    local label="$1"
    local pattern="$2"
    local match
    # -P is PCRE; works on macOS grep 2.6+ via BSD `grep -E`, so use egrep-compatible instead
    match=$(printf '%s\n' "$diff" | grep -nE "$pattern" || true)
    if [ -n "$match" ]; then
        echo "[pre-commit] BLOCKED: $label"
        printf '%s\n' "$match" | head -5 | sed 's/^/    /'
        echo
        hits=$((hits + 1))
    fi
}

# Phone numbers with country code (+ followed by 2-3 digits, then 4+ more digits,
# optionally separated by spaces/dashes). Catches international-format numbers.
check "phone-like number with country code" '\+[0-9]{1,3}[ -]?[0-9]{2,}[ -]?[0-9]{4,}'

# Personal email domains. Allow noreply, example, test, and common placeholder
# patterns like user@example.com.
check "personal email address" '[A-Za-z0-9._%+-]+@(gmail|icloud|me|yahoo|outlook|hotmail|proton|protonmail|aol|gmx|web)\.(com|de|me|net|ch)\b'

# IBAN: 2 letters + 2 digits + 10-30 alphanumerics. Skip if a shorter match to
# reduce false positives on arbitrary strings.
check "IBAN-like string" '\b[A-Z]{2}[0-9]{2}[A-Z0-9]{12,30}\b'

# SWIFT/BIC code: 8 or 11 uppercase alphanumerics, often grouped.
check "SWIFT/BIC-like code" '\b[A-Z]{4}[A-Z]{2}[A-Z0-9]{2}([A-Z0-9]{3})?\b'

if [ "$hits" -gt 0 ]; then
    echo "[pre-commit] $hits check(s) failed. If these are false positives, either"
    echo "             genericize the values or run: git commit --no-verify"
    exit 1
fi

exit 0
